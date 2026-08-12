#!/usr/bin/env python3
"""Stage and execute an untrusted candidate without oracle capabilities."""

from __future__ import annotations

import hashlib
import os
import pathlib
import shutil
import signal
import stat
import subprocess
import tempfile
from dataclasses import dataclass


class CandidateIsolationError(Exception):
    pass


MINIMAL_CANDIDATE_ENVIRONMENT = {
    "LANG": "C",
    "LC_ALL": "C",
    "NO_COLOR": "1",
    "PATH": "/empty",
    "TMPDIR": "/tmp",
    "TZ": "UTC",
}

RUNTIME_FILES = (
    pathlib.Path("/lib64/ld-linux-x86-64.so.2"),
    pathlib.Path("/lib/x86_64-linux-gnu/libc.so.6"),
    pathlib.Path("/lib/x86_64-linux-gnu/libm.so.6"),
)


def _sha256_fd(fd: int) -> str:
    digest = hashlib.sha256()
    os.lseek(fd, 0, os.SEEK_SET)
    while chunk := os.read(fd, 1024 * 1024):
        digest.update(chunk)
    os.lseek(fd, 0, os.SEEK_SET)
    return digest.hexdigest()


def _copy_fd(fd: int, destination: pathlib.Path) -> None:
    with destination.open("xb") as target:
        while chunk := os.read(fd, 1024 * 1024):
            target.write(chunk)
        target.flush()
        os.fsync(target.fileno())


@dataclass
class IsolatedCandidate:
    root: pathlib.Path
    source_sha256: str
    source: pathlib.Path
    source_identity: tuple[int, int, int, int]
    _temporary: tempfile.TemporaryDirectory[str]

    @classmethod
    def stage(cls, candidate: pathlib.Path) -> "IsolatedCandidate":
        if os.geteuid() != 0:
            raise CandidateIsolationError("candidate isolation requires root")
        flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
        try:
            fd = os.open(candidate, flags)
        except OSError as exc:
            raise CandidateIsolationError(f"cannot open candidate {candidate}: {exc}") from exc
        try:
            metadata = os.fstat(fd)
            if not stat.S_ISREG(metadata.st_mode):
                raise CandidateIsolationError("candidate must be a regular file")
            if metadata.st_size <= 0:
                raise CandidateIsolationError("candidate must not be empty")
            source_digest = _sha256_fd(fd)
            temporary = tempfile.TemporaryDirectory(prefix="jq-candidate-root-")
            root = pathlib.Path(temporary.name)
            root.chmod(0o755)
            (root / "work").mkdir(mode=0o700)
            (root / "tmp").mkdir(mode=0o700)
            (root / "empty").mkdir(mode=0o555)
            # core:os resolves an opened file's display path through
            # /proc/self/fd. A sealed synthetic entry supplies no host procfs
            # view and names only the already-open candidate input descriptor.
            (root / "proc/self/fd").mkdir(parents=True, mode=0o555)
            (root / "proc/self/fd/3").symlink_to("/candidate-input")
            os.chown(root / "work", 65534, 65534)
            os.chown(root / "tmp", 65534, 65534)
            staged = root / "candidate"
            _copy_fd(fd, staged)
            staged.chmod(0o555)
            staged_fd = os.open(staged, os.O_RDONLY | os.O_CLOEXEC)
            try:
                staged_digest = _sha256_fd(staged_fd)
            finally:
                os.close(staged_fd)
            if staged_digest != source_digest:
                raise CandidateIsolationError("candidate changed during immutable staging")
            after = os.fstat(fd)
            if (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) != (
                metadata.st_dev,
                metadata.st_ino,
                metadata.st_size,
                metadata.st_mtime_ns,
            ) or _sha256_fd(fd) != source_digest:
                raise CandidateIsolationError("candidate source changed during staging")
            for runtime_file in RUNTIME_FILES:
                if not runtime_file.is_file():
                    raise CandidateIsolationError(
                        f"required candidate runtime is missing: {runtime_file}"
                    )
                destination = root / runtime_file.relative_to("/")
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(runtime_file, destination, follow_symlinks=True)
                destination.chmod(0o555)
            return cls(
                root,
                source_digest,
                candidate,
                (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns),
                temporary,
            )
        except Exception:
            if "temporary" in locals():
                temporary.cleanup()
            raise
        finally:
            os.close(fd)

    def close(self) -> None:
        self._temporary.cleanup()

    def verify_source(self) -> None:
        flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
        try:
            fd = os.open(self.source, flags)
        except OSError as exc:
            raise CandidateIsolationError(
                f"candidate handoff source is unavailable: {exc}"
            ) from exc
        try:
            metadata = os.fstat(fd)
            identity = (
                metadata.st_dev,
                metadata.st_ino,
                metadata.st_size,
                metadata.st_mtime_ns,
            )
            if identity != self.source_identity or _sha256_fd(fd) != self.source_sha256:
                raise CandidateIsolationError("candidate changed after immutable staging")
        finally:
            os.close(fd)

    def _enter(self) -> None:
        os.unshare(os.CLONE_NEWNET)
        os.chroot(self.root)
        os.chdir("/work")
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)

    def stage_arguments(self, argv: list[str]) -> list[str]:
        """Copy explicit regular-file operands into the capability root."""
        rewritten: list[str] = []
        inputs = self.root / "inputs"
        for index, argument in enumerate(argv):
            source = pathlib.Path(argument)
            if not source.is_absolute() or not source.is_file():
                rewritten.append(argument)
                continue
            metadata = source.lstat()
            if not stat.S_ISREG(metadata.st_mode):
                raise CandidateIsolationError(
                    f"candidate input must be a regular file: {source}"
                )
            inputs.mkdir(mode=0o555, exist_ok=True)
            destination = inputs / f"{index}-{source.name}"
            if destination.exists():
                destination.unlink()
            shutil.copyfile(source, destination, follow_symlinks=False)
            destination.chmod(0o444)
            rewritten.append(f"/inputs/{destination.name}")
        return rewritten

    def popen(self, argv: list[str], **kwargs: object) -> subprocess.Popen[bytes]:
        if any("\x00" in argument for argument in argv):
            raise CandidateIsolationError("candidate argument contains NUL")
        return subprocess.Popen(
            ["/candidate", *argv],
            cwd="/",
            env=MINIMAL_CANDIDATE_ENVIRONMENT,
            close_fds=True,
            start_new_session=True,
            preexec_fn=self._enter,
            **kwargs,
        )

    def run(
        self, argv: list[str], stdin: bytes = b"", timeout: float = 5.0
    ) -> subprocess.CompletedProcess[bytes]:
        self.verify_source()
        argv = self.stage_arguments(argv)
        process = self.popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            stdout, stderr = process.communicate(stdin, timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
            raise CandidateIsolationError("isolated candidate timed out")
        return subprocess.CompletedProcess(
            ["/candidate", *argv], process.returncode, stdout, stderr
        )


__all__ = [
    "CandidateIsolationError",
    "IsolatedCandidate",
    "MINIMAL_CANDIDATE_ENVIRONMENT",
]
