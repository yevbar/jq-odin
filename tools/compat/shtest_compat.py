#!/usr/bin/env python3
"""Compare explicit process cases from jq's shtest without evaluating shell."""

from __future__ import annotations

import argparse
import base64
import binascii
import contextlib
import ctypes
import fcntl
import fnmatch
import hashlib
import json
import math
import os
import pathlib
import platform
import re
import select
import selectors
import secrets
import shlex
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from typing import Any


SCHEMA_VERSION = 1
REPORT_SCHEMA_VERSION = 5
EXPECTED_ORACLE_VERSION = "jq-1.8.1"
CASE_ID_RE = re.compile(r"[a-z0-9]+(?:[._-][a-z0-9]+)*\Z")
SOURCE_RE = re.compile(r"upstream/jq/tests/[A-Za-z0-9._/-]+\Z")
MAX_TIMEOUT_SECONDS = 60.0
MAX_CAPTURE_BYTES = 1024 * 1024
PROCESS_SETUP_SECONDS = 1.0
PIPE_DRAIN_SECONDS = 0.25
PROCESS_CLEANUP_SECONDS = 0.5
PROCESS_SCAN_ENTRY_BUDGET = 65536
PROCESS_IDENTITY_READ_BUDGET = 32768
PROCESS_DISCOVERY_BUDGET = 4096
WORKSPACE_CLEANUP_ENTRY_BUDGET = 32768
WORKSPACE_CLEANUP_BYTE_BUDGET = 64 * 1024 * 1024
WORKSPACE_CLEANUP_WORK_BUDGET = 65536
READ_CHUNK_BYTES = 64 * 1024
EXECUTABLE_CAPTURE_SECONDS = 5.0
MAX_EXECUTABLE_CAPTURE_BYTES = 128 * 1024 * 1024
MAX_ORIGIN_DEPENDENCIES = 256
SHEBANG_PREFIX_BYTES = 256
EXECUTABLE_MODE_SEAL = getattr(fcntl, "F_SEAL_EXEC", 0x0020)
MS_NOSUID = 2
MS_NODEV = 4
MS_REC = 16384
MS_PRIVATE = 1 << 18
_SUBREAPER_ENABLED = False
PTRACE_TRACEME = 0
PTRACE_CONT = 7
PTRACE_DETACH = 17
PTRACE_SETOPTIONS = 0x4200
PTRACE_O_TRACEEXEC = 0x10
PTRACE_EVENT_EXEC = 4


class HarnessError(Exception):
    pass


class ExecutableCaptureTimeout(HarnessError):
    pass


class ProcessSetupError(HarnessError):
    """A bounded pre-execution failure with an existing schema-v5 stage."""

    def __init__(
        self,
        role: str,
        step: str,
        message: str,
        *,
        timed_out: bool,
        result: ProcessResult | None = None,
    ) -> None:
        super().__init__(message)
        self.role = role
        self.step = step
        self.timed_out = timed_out
        self.result = result
        self.report_stage = (
            "process_setup_timeout" if timed_out else "process_setup_failure"
        )


class ProcessStatusError(HarnessError):
    """The adapter's exclusive child wait status was consumed elsewhere."""

    def __init__(self, pid: int, args: list[str]) -> None:
        super().__init__(
            f"lost exclusive wait-status ownership for child {pid}: "
            f"{shlex.join(args)}"
        )
        self.pid = pid
        self.command_args = args
        self.role: str | None = None
        self.result: ProcessResult | None = None


class VersionProbeError(HarnessError):
    def __init__(self, message: str, role: str, result: ProcessResult) -> None:
        super().__init__(message)
        self.role = role
        self.result = result


class ContainmentError(HarnessError):
    """Infrastructure-fatal loss of authority over an untrusted invocation."""

    def __init__(self, message: str, role: str, result: ProcessResult) -> None:
        super().__init__(message)
        self.role = role
        self.result = result


class DuplicateObjectKeyError(ValueError):
    pass


@dataclass(frozen=True)
class Provenance:
    source: str
    line_start: int
    line_end: int


@dataclass(frozen=True)
class ProcessCase:
    ordinal: int
    case_id: str
    provenance: Provenance
    argv: tuple[str, ...] | None
    stdin: bytes | None
    timeout_seconds: float | None
    skip_reason: str | None

    @property
    def kind(self) -> str:
        return "skip" if self.skip_reason is not None else "run"


@dataclass
class ProcessResult:
    argv: list[str]
    working_directory: str
    exit_status: int | None
    signal: int | None
    timed_out: bool
    duration_ms: int
    stdout_b64: str
    stderr_b64: str
    stdout_truncated: bool
    stderr_truncated: bool
    output_limit_exceeded: bool
    pipe_drain_timed_out: bool
    descendant_cleanup_required: bool
    cleanup_incomplete: bool
    quarantined_path: str | None = None


@dataclass(frozen=True)
class ChildSetupOutcome:
    failure: tuple[str, str] | None
    execution_started: float | None


@dataclass
class CapturedDependency:
    """One sealed path-relative ELF dependency captured with its consumer."""

    path: pathlib.Path
    fd: int
    sha256: str
    source_device: int
    source_inode: int
    parent_fd: int
    anchor_fd: int
    hwcaps_root: pathlib.Path | None = None

    def close(self) -> None:
        if self.parent_fd >= 0:
            os.close(self.parent_fd)
            self.parent_fd = -1
        if self.anchor_fd >= 0:
            os.close(self.anchor_fd)
            self.anchor_fd = -1
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1


@dataclass
class ExecutableImage:
    """A sealed Linux snapshot whose digest is the identity that is executed."""

    path: pathlib.Path
    label: str
    fd: int
    sha256: str
    is_script: bool
    source_device: int
    source_inode: int
    parent_fd: int
    anchor_fd: int
    interpreter: ExecutableImage | None = None
    elf_interpreter: ExecutableImage | None = None
    origin_dependencies: tuple[CapturedDependency, ...] = ()

    def close(self) -> None:
        if self.interpreter is not None:
            self.interpreter.close()
            self.interpreter = None
        if self.elf_interpreter is not None:
            self.elf_interpreter.close()
            self.elf_interpreter = None
        for dependency in self.origin_dependencies:
            dependency.close()
        self.origin_dependencies = ()
        if self.parent_fd >= 0:
            os.close(self.parent_fd)
            self.parent_fd = -1
        if self.anchor_fd >= 0:
            os.close(self.anchor_fd)
            self.anchor_fd = -1
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1


@dataclass
class ExecutableCaptureBudget:
    deadline: float
    remaining_bytes: int = MAX_EXECUTABLE_CAPTURE_BYTES


@dataclass(frozen=True)
class DynamicLoaderContext:
    """The program interpreter whose dynamic-string rules apply to a tree."""

    interpreter: pathlib.Path


@dataclass(frozen=True)
class DynamicLoaderTokens:
    library: str
    platform: str
    hwcaps: tuple[str, ...]


_DYNAMIC_LOADER_TOKEN_CACHE: dict[tuple[int, int], DynamicLoaderTokens] = {}


@dataclass(frozen=True)
class ElfDynamicSearch:
    """Loader search state extracted from one sealed ELF image."""

    rpath: tuple[pathlib.Path, ...]
    runpath: tuple[pathlib.Path, ...]
    needed: tuple[str, ...]
    loader: DynamicLoaderContext | None
    program_interpreter: pathlib.Path | None


@dataclass(frozen=True)
class PathMaterial:
    path: pathlib.Path
    fd: int
    sha256: str
    executable: bool
    parent_fd: int
    anchor_fd: int
    hwcaps_root: pathlib.Path | None = None


@dataclass(frozen=True)
class PathLaunch:
    anchor: pathlib.Path
    directory_fd: int
    materials: tuple[PathMaterial, ...]
    staging_path: pathlib.Path


@dataclass
class TraversalBudget:
    """One absolute deadline and cumulative process/filesystem work allowance."""

    deadline: float
    scan_entries: int = PROCESS_SCAN_ENTRY_BUDGET
    identity_reads: int = PROCESS_IDENTITY_READ_BUDGET
    discoveries: int = PROCESS_DISCOVERY_BUDGET
    workspace_entries: int = WORKSPACE_CLEANUP_ENTRY_BUDGET
    workspace_bytes: int = WORKSPACE_CLEANUP_BYTE_BUDGET
    workspace_work: int = WORKSPACE_CLEANUP_WORK_BUDGET

    def take_scan_entry(self) -> bool:
        if time.monotonic() >= self.deadline or self.scan_entries <= 0:
            return False
        self.scan_entries -= 1
        return True

    def take_identity_read(self) -> bool:
        if time.monotonic() >= self.deadline or self.identity_reads <= 0:
            return False
        self.identity_reads -= 1
        return True

    def take_discovery(self) -> bool:
        if time.monotonic() >= self.deadline or self.discoveries <= 0:
            return False
        self.discoveries -= 1
        return True

    def take_workspace_entry(self, byte_count: int) -> bool:
        if (
            time.monotonic() >= self.deadline
            or self.workspace_entries <= 0
            or byte_count < 0
            or byte_count > self.workspace_bytes
        ):
            return False
        self.workspace_entries -= 1
        self.workspace_bytes -= byte_count
        return True

    def take_workspace_work(self) -> bool:
        if time.monotonic() >= self.deadline or self.workspace_work <= 0:
            return False
        self.workspace_work -= 1
        return True


@dataclass
class ProcessSnapshot:
    children: dict[int, set[int]]
    identities: dict[int, tuple[int, int]]
    complete: bool


@dataclass(frozen=True)
class ProcessTreeCleanupResult:
    complete: bool
    descendant_cleanup_required: bool


@dataclass
class DiscoveryResult:
    identities: set[tuple[int, int]]
    complete: bool


@dataclass(frozen=True)
class ProcessGroupIdentity:
    leader_pid: int
    leader_start_time: int
    session_id: int
    process_group_id: int


@dataclass(frozen=True)
class WorkspaceIdentity:
    device: int
    inode: int
    mount_id: int


@dataclass
class WorkspaceAuthority:
    """Descriptors and identities retained before an untrusted process starts."""

    path: pathlib.Path
    root_fd: int
    parent_fd: int
    identity: WorkspaceIdentity
    parent_identity: WorkspaceIdentity

    def close(self) -> None:
        for field in ("root_fd", "parent_fd"):
            descriptor = getattr(self, field)
            if descriptor >= 0:
                os.close(descriptor)
                setattr(self, field, -1)


@dataclass(frozen=True)
class WorkspaceCleanupResult:
    complete: bool
    quarantined_path: str | None


@dataclass
class WorkspaceLocation:
    parent_fd: int
    name: str

    def close(self) -> None:
        if self.parent_fd >= 0:
            os.close(self.parent_fd)
            self.parent_fd = -1


def repository_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[2]


def absolute_unresolved(path: pathlib.Path) -> pathlib.Path:
    """Make a user path absolute without dereferencing its final symlink."""
    return pathlib.Path(os.path.abspath(path))


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateObjectKeyError(key)
        result[key] = value
    return result


def require_fields(
    value: dict[str, Any], required: set[str], context: str
) -> None:
    actual = set(value)
    missing = sorted(required - actual)
    unknown = sorted(actual - required)
    if missing:
        raise HarnessError(f"{context}: missing fields: {', '.join(missing)}")
    if unknown:
        raise HarnessError(f"{context}: unknown fields: {', '.join(unknown)}")


def decode_bytes(value: Any, context: str) -> bytes:
    if not isinstance(value, str):
        raise HarnessError(f"{context}: must be a Base64 string")
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise HarnessError(f"{context}: invalid Base64") from exc
    if base64.b64encode(raw).decode("ascii") != value:
        raise HarnessError(f"{context}: Base64 must use canonical padding")
    return raw


def positive_int(value: Any, context: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise HarnessError(f"{context}: must be a positive integer")
    return value


def timeout_value(value: Any, context: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise HarnessError(f"{context}: must be a finite number")
    try:
        result = float(value)
    except OverflowError as exc:
        raise HarnessError(
            f"{context}: must be greater than zero and at most "
            f"{MAX_TIMEOUT_SECONDS:g}"
        ) from exc
    if not math.isfinite(result) or not 0 < result <= MAX_TIMEOUT_SECONDS:
        raise HarnessError(
            f"{context}: must be greater than zero and at most "
            f"{MAX_TIMEOUT_SECONDS:g}"
        )
    return result


def parse_provenance(value: Any, context: str) -> Provenance:
    if not isinstance(value, dict):
        raise HarnessError(f"{context}: must be an object")
    require_fields(value, {"source", "line_start", "line_end"}, context)
    source = value["source"]
    if not isinstance(source, str) or not SOURCE_RE.fullmatch(source):
        raise HarnessError(f"{context}.source: invalid upstream test path")
    line_start = positive_int(value["line_start"], f"{context}.line_start")
    line_end = positive_int(value["line_end"], f"{context}.line_end")
    if line_end < line_start:
        raise HarnessError(f"{context}: line_end precedes line_start")
    return Provenance(source, line_start, line_end)


def parse_case(value: Any, ordinal: int) -> ProcessCase:
    context = f"case {ordinal}"
    if not isinstance(value, dict):
        raise HarnessError(f"{context}: must be an object")
    kind = value.get("kind")
    if kind == "run":
        require_fields(
            value,
            {"id", "kind", "provenance", "argv", "stdin_b64", "timeout_seconds"},
            context,
        )
    elif kind == "skip":
        require_fields(value, {"id", "kind", "provenance", "reason"}, context)
    else:
        raise HarnessError(f"{context}.kind: must be 'run' or 'skip'")

    case_id = value["id"]
    if not isinstance(case_id, str) or not CASE_ID_RE.fullmatch(case_id):
        raise HarnessError(f"{context}.id: invalid case ID")
    provenance = parse_provenance(value["provenance"], f"{context}.provenance")

    if kind == "skip":
        reason = value["reason"]
        if not isinstance(reason, str) or not reason.strip():
            raise HarnessError(f"{context}.reason: must be a non-empty string")
        return ProcessCase(ordinal, case_id, provenance, None, None, None, reason)

    argv = value["argv"]
    if not isinstance(argv, list) or not argv:
        raise HarnessError(f"{context}.argv: must be a non-empty array")
    if any(not isinstance(arg, str) for arg in argv):
        raise HarnessError(f"{context}.argv: every element must be a string")
    if any("\x00" in arg for arg in argv):
        raise HarnessError(f"{context}.argv: NUL is not representable in argv")
    stdin = decode_bytes(value["stdin_b64"], f"{context}.stdin_b64")
    timeout = timeout_value(value["timeout_seconds"], f"{context}.timeout_seconds")
    return ProcessCase(
        ordinal, case_id, provenance, tuple(argv), stdin, timeout, None
    )


def load_catalog(path: pathlib.Path) -> list[ProcessCase]:
    try:
        with path.open("r", encoding="utf-8") as source:
            value = json.load(source, object_pairs_hook=unique_object)
    except DuplicateObjectKeyError as exc:
        raise HarnessError(f"catalog contains duplicate object key: {exc}") from exc
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise HarnessError(f"cannot read catalog {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise HarnessError("catalog: must be an object")
    require_fields(value, {"schema_version", "cases"}, "catalog")
    if type(value["schema_version"]) is not int or value["schema_version"] != SCHEMA_VERSION:
        raise HarnessError(f"catalog.schema_version: must equal {SCHEMA_VERSION}")
    if not isinstance(value["cases"], list) or not value["cases"]:
        raise HarnessError("catalog.cases: must be a non-empty array")
    cases = [parse_case(entry, index) for index, entry in enumerate(value["cases"], 1)]
    seen: set[str] = set()
    for case in cases:
        if case.case_id in seen:
            raise HarnessError(f"catalog contains duplicate case ID: {case.case_id}")
        seen.add(case.case_id)
    return cases


def select_cases(cases: list[ProcessCase], patterns: list[str]) -> list[ProcessCase]:
    if not patterns:
        return cases
    return [
        case
        for case in cases
        if any(fnmatch.fnmatchcase(case.case_id, pattern) for pattern in patterns)
    ]


def encoded(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def process_environment(working_directory: pathlib.Path) -> dict[str, str]:
    return {
        "HOME": str(working_directory),
        "LANG": "C",
        "LC_ALL": "C",
        "NO_COLOR": "1",
        "PATH": os.defpath,
        "TMPDIR": str(working_directory),
        "TZ": "UTC",
    }


def execution_deadline_reached(now: float, deadline: float) -> bool:
    """The absolute deadline itself belongs to the timed-out interval."""
    return now >= deadline


def execution_deadline_from_observation(
    execution_started: float, timeout: float
) -> float:
    """Anchor case runtime to the parent's first confirmed-exec observation."""
    return execution_started + timeout


def require_linux_process_primitives() -> None:
    libc = ctypes.CDLL(None)
    if (
        platform.system() != "Linux"
        or not hasattr(os, "memfd_create")
        or not hasattr(os, "O_PATH")
        or not hasattr(os, "O_NOFOLLOW")
        or not hasattr(os, "unshare")
        or not hasattr(os, "CLONE_NEWUSER")
        or not hasattr(os, "CLONE_NEWNS")
        or not hasattr(os, "pidfd_open")
        or not hasattr(signal, "pidfd_send_signal")
        or getattr(libc, "renameat2", None) is None
        or getattr(libc, "ptrace", None) is None
    ):
        raise HarnessError(
            "shtest process execution requires Linux memfd seals, O_PATH, "
            "renameat2, /proc, ptrace, pidfds, and prctl"
        )


def ptrace_linux(request: int, pid: int = 0, data: int = 0) -> None:
    """Issue the small ptrace subset used to prove setup-child exec."""
    libc = ctypes.CDLL(None, use_errno=True)
    ptrace = libc.ptrace
    ptrace.argtypes = [
        ctypes.c_uint,
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    ptrace.restype = ctypes.c_long
    if ptrace(request, pid, None, ctypes.c_void_p(data)) == -1:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def mount_linux(
    source: bytes | None,
    target: pathlib.Path,
    filesystem: bytes | None,
    flags: int,
    data: bytes | None,
) -> None:
    """Call mount(2), raising before exec when launch isolation is unavailable."""
    libc = ctypes.CDLL(None, use_errno=True)
    mount = libc.mount
    mount.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_ulong,
        ctypes.c_char_p,
    ]
    mount.restype = ctypes.c_int
    if mount(source, os.fsencode(target), filesystem, flags, data) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(target))


def mount_overlay_fd(
    lower_fd: int,
    target_fd: int,
    upper: pathlib.Path,
    work: pathlib.Path,
) -> None:
    """Resolve retained directory authority only at the final mount step."""
    if lower_fd != target_fd:
        raise OSError("overlay lower and target authorities differ")
    directory = pathlib.Path(os.readlink(f"/proc/self/fd/{target_fd}"))
    if any(
        character in str(path)
        for path in (directory, upper, work)
        for character in ",:"
    ):
        raise OSError("path overlay paths contain unsupported separators")
    options = f"lowerdir={directory},upperdir={upper},workdir={work}".encode()
    mount_linux(b"overlay", directory, b"overlay", 0, options)


def write_namespace_mapping(path: str, value: str) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CLOEXEC)
    try:
        os.write(descriptor, value.encode("ascii"))
    finally:
        os.close(descriptor)


def path_namespace_anchor(path: pathlib.Path) -> pathlib.Path:
    """Return the stable top-level mount boundary containing an absolute path."""
    if not path.is_absolute() or len(path.parts) < 3:
        raise HarnessError(f"executable path has no private launch anchor: {path}")
    return pathlib.Path(path.anchor) / path.parts[1]


def create_path_staging(anchors: set[pathlib.Path]) -> pathlib.Path:
    """Create an empty host-visible staging point outside every overlaid anchor."""
    for base in (
        pathlib.Path("/dev/shm"),
        pathlib.Path("/tmp"),
        pathlib.Path("/run"),
    ):
        if (
            any(base.is_relative_to(anchor) for anchor in anchors)
            or not base.is_dir()
        ):
            continue
        try:
            return pathlib.Path(
                tempfile.mkdtemp(prefix=".shtest-path-launch-", dir=base)
            )
        except OSError:
            continue
    raise OSError("cannot create private path staging outside namespace anchors")


def normalize_path_launches(
    launches: tuple[PathLaunch, ...],
) -> tuple[PathLaunch, ...]:
    """Deduplicate launches and order every ancestor before its descendants."""
    grouped: dict[
        pathlib.Path,
        tuple[int, pathlib.Path, dict[pathlib.Path, PathMaterial], set[pathlib.Path]],
    ] = {}
    for launch in launches:
        if launch.anchor not in grouped:
            grouped[launch.anchor] = (launch.directory_fd, launch.staging_path, {}, set())
        directory_fd, staging_path, materials, hwcaps_roots = grouped[launch.anchor]
        if directory_fd != launch.directory_fd:
            raise OSError("path launches have conflicting authorities for one anchor")
        if str(launch.staging_path) < str(staging_path):
            staging_path = launch.staging_path
            grouped[launch.anchor] = (
                directory_fd,
                staging_path,
                materials,
                hwcaps_roots,
            )
        for material in launch.materials:
            prior = materials.get(material.path)
            if prior is not None and (
                prior.sha256 != material.sha256
                or prior.executable != material.executable
            ):
                raise OSError("path launches contain conflicting sealed material")
            if prior is None or (material.fd, material.parent_fd) < (
                prior.fd,
                prior.parent_fd,
            ):
                materials[material.path] = material
            if material.hwcaps_root is not None:
                if not material.hwcaps_root.is_relative_to(launch.anchor):
                    raise OSError("glibc-hwcaps seal escaped its namespace anchor")
                hwcaps_roots.add(material.hwcaps_root)

    normalized = [
        PathLaunch(
            anchor,
            directory_fd,
            tuple(sorted(materials.values(), key=lambda item: str(item.path))),
            staging_path,
        )
        for anchor, (
            directory_fd,
            staging_path,
            materials,
            _hwcaps_roots,
        ) in grouped.items()
    ]
    return tuple(
        sorted(
            normalized,
            key=lambda launch: (
                len(launch.anchor.parts),
                str(launch.anchor),
                str(launch.staging_path),
            ),
        )
    )


def prepare_path_launches(launches: tuple[PathLaunch, ...]) -> None:
    """Expose sealed bytes without reopening any captured source parent."""
    launches = normalize_path_launches(launches)
    effective_uid = os.geteuid()
    effective_gid = os.getegid()
    os.unshare(os.CLONE_NEWUSER | os.CLONE_NEWNS)
    try:
        write_namespace_mapping("/proc/self/setgroups", "deny")
    except FileNotFoundError:
        pass
    write_namespace_mapping("/proc/self/uid_map", f"{effective_uid} {effective_uid} 1")
    write_namespace_mapping("/proc/self/gid_map", f"{effective_gid} {effective_gid} 1")
    mount_linux(None, pathlib.Path("/"), None, MS_REC | MS_PRIVATE, None)

    def materialize(material: PathMaterial, destination: pathlib.Path) -> None:
        destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        materialized_fd = os.open(
            destination,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC,
            0o500 if material.executable else 0o400,
        )
        digest = hashlib.sha256()
        offset = 0
        try:
            size = os.fstat(material.fd).st_size
            while offset < size:
                chunk = os.pread(
                    material.fd, min(1024 * 1024, size - offset), offset
                )
                if not chunk:
                    raise OSError("captured path material ended unexpectedly")
                digest.update(chunk)
                view = memoryview(chunk)
                while view:
                    written = os.write(materialized_fd, view)
                    view = view[written:]
                offset += len(chunk)
        finally:
            os.close(materialized_fd)
        if digest.hexdigest() != material.sha256:
            raise OSError("materialized path failed captured-image validation")

    for launch in launches:
        mount_linux(
            b"tmpfs",
            launch.staging_path,
            b"tmpfs",
            MS_NOSUID | MS_NODEV,
            b"mode=0700,size=268435456",
        )
        upper = launch.staging_path / "upper"
        work = launch.staging_path / "work"
        upper.mkdir(mode=0o700)
        work.mkdir(mode=0o700)
        reported_hwcaps_roots = sorted(
            {
                material.hwcaps_root
                for material in launch.materials
                if material.hwcaps_root is not None
            },
            key=lambda root: (len(root.parts), str(root)),
        )
        hwcaps_roots: list[pathlib.Path] = []
        for root in reported_hwcaps_roots:
            if not any(root.is_relative_to(ancestor) for ancestor in hwcaps_roots):
                hwcaps_roots.append(root)
        for root in hwcaps_roots:
            assert root is not None
            try:
                relative_root = root.relative_to(launch.anchor)
            except ValueError as exc:
                raise OSError("glibc-hwcaps seal escaped its namespace anchor") from exc
            (upper / relative_root).mkdir(mode=0o700, parents=True, exist_ok=True)
        for material in launch.materials:
            if any(material.path.is_relative_to(root) for root in hwcaps_roots):
                continue
            try:
                relative = material.path.relative_to(launch.anchor)
            except ValueError as exc:
                raise OSError("path launch escaped its namespace anchor") from exc
            materialize(material, upper / relative)

        if any(
            character in str(path)
            for path in (upper, work)
            for character in ",:"
        ):
            raise OSError("path overlay paths contain unsupported separators")
        mount_overlay_fd(
            launch.directory_fd,
            launch.directory_fd,
            upper,
            work,
        )
        for root in hwcaps_roots:
            assert root is not None
            root.mkdir(mode=0o700, parents=True, exist_ok=True)
            mount_linux(
                b"tmpfs",
                root,
                b"tmpfs",
                MS_NOSUID | MS_NODEV,
                b"mode=0700,size=268435456",
            )
            for material in launch.materials:
                if material.path.is_relative_to(root):
                    materialize(material, root / material.path.relative_to(root))


def prepare_script_path_launch(
    script_fd: int,
    script_path: pathlib.Path,
    script_parent_fd: int,
    staging_path: pathlib.Path,
    expected_sha256: str,
) -> None:
    """Compatibility wrapper for the single-script private path launch."""
    prepare_path_launches(
        (
            PathLaunch(
                script_path.parent,
                script_parent_fd,
                (
                    PathMaterial(
                        script_path,
                        script_fd,
                        expected_sha256,
                        True,
                        script_parent_fd,
                        script_parent_fd,
                    ),
                ),
                staging_path,
            ),
        ),
    )


def enable_child_subreaper() -> None:
    """Adopt orphaned descendants so session escapes can still be reaped."""
    global _SUBREAPER_ENABLED
    if _SUBREAPER_ENABLED:
        return
    require_linux_process_primitives()
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        error = ctypes.get_errno()
        raise HarnessError(f"cannot enable Linux child subreaper: {os.strerror(error)}")
    _SUBREAPER_ENABLED = True


def read_executable_source(
    source_fd: int,
    image_fd: int,
    path: pathlib.Path,
    label: str,
    budget: ExecutableCaptureBudget,
) -> tuple[str, bytes]:
    """Copy and hash a source under the capture operation's outer alarm."""
    digest = hashlib.sha256()
    prefix = b""
    while True:
        chunk = os.read(source_fd, 1024 * 1024)
        if not chunk:
            break
        budget.remaining_bytes -= len(chunk)
        if budget.remaining_bytes < 0:
            raise HarnessError(
                f"{label} executable and origin dependencies exceed the "
                f"{MAX_EXECUTABLE_CAPTURE_BYTES}-byte capture limit: {path}"
            )
        if len(prefix) < SHEBANG_PREFIX_BYTES:
            prefix = (prefix + chunk)[:SHEBANG_PREFIX_BYTES]
        digest.update(chunk)
        view = memoryview(chunk)
        while view:
            written = os.write(image_fd, view)
            view = view[written:]
    return digest.hexdigest(), prefix


@contextlib.contextmanager
def executable_capture_alarm(
    budget: ExecutableCaptureBudget, path: pathlib.Path, label: str
) -> Any:
    """Bound one complete initial and recursive executable capture operation."""
    try:
        previous_handler = signal.getsignal(signal.SIGALRM)
        previous_timer = signal.getitimer(signal.ITIMER_REAL)
    except (AttributeError, OSError, ValueError) as exc:
        raise HarnessError(
            f"cannot establish {label} executable capture deadline: {exc}"
        ) from exc
    def capture_timed_out(signum: int, frame: object) -> None:
        del signum, frame
        raise ExecutableCaptureTimeout(
            f"{label} executable capture exceeded "
            f"{EXECUTABLE_CAPTURE_SECONDS:g} seconds: {path}"
        )

    try:
        signal.signal(signal.SIGALRM, capture_timed_out)
        remaining_time = budget.deadline - time.monotonic()
        if remaining_time <= 0:
            raise ExecutableCaptureTimeout(
                f"{label} executable capture exceeded "
                f"{EXECUTABLE_CAPTURE_SECONDS:g} seconds: {path}"
            )
        signal.setitimer(signal.ITIMER_REAL, remaining_time)
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)
        signal.setitimer(signal.ITIMER_REAL, *previous_timer)


def active_dynamic_loader_path() -> pathlib.Path:
    """Return the loader mapped at this process's kernel-provided AT_BASE."""
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        getauxval = libc.getauxval
    except AttributeError as exc:
        raise HarnessError("the Linux C runtime does not expose AT_BASE") from exc
    getauxval.argtypes = [ctypes.c_ulong]
    getauxval.restype = ctypes.c_ulong
    loader_base = int(getauxval(7))  # AT_BASE
    if loader_base == 0:
        raise HarnessError("cannot identify the active Linux dynamic loader")
    try:
        maps = pathlib.Path("/proc/self/maps").read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise HarnessError(f"cannot inspect the active Linux dynamic loader: {exc}") from exc
    for line in maps.splitlines():
        fields = line.split(None, 5)
        if len(fields) != 6 or not fields[5].startswith("/"):
            continue
        try:
            start_text, end_text = fields[0].split("-", 1)
            start, end = int(start_text, 16), int(end_text, 16)
        except ValueError:
            continue
        if start <= loader_base < end:
            if fields[5].endswith(" (deleted)"):
                raise HarnessError("the active Linux dynamic loader was deleted")
            return pathlib.Path(fields[5])
    raise HarnessError("cannot locate the active Linux dynamic loader mapping")


def dynamic_loader_tokens(
    loader: DynamicLoaderContext,
    path: pathlib.Path,
    label: str,
    budget: ExecutableCaptureBudget,
) -> DynamicLoaderTokens:
    """Query the exact active glibc loader for its configured token values."""
    active_loader = active_dynamic_loader_path()
    try:
        requested = loader.interpreter.stat()
        active = active_loader.stat()
    except OSError as exc:
        raise HarnessError(
            f"cannot verify {label} ELF dynamic loader for {path}: {exc}"
        ) from exc
    if (requested.st_dev, requested.st_ino) != (active.st_dev, active.st_ino):
        raise HarnessError(
            f"{label} ELF dynamic tokens require the active glibc loader "
            f"{active_loader}, not {loader.interpreter}: {path}"
        )
    cache_key = (active.st_dev, active.st_ino)
    cached = _DYNAMIC_LOADER_TOKEN_CACHE.get(cache_key)
    if cached is not None:
        return cached

    def loader_query(option: str) -> subprocess.CompletedProcess[bytes]:
        timeout = budget.deadline - time.monotonic()
        if timeout <= 0:
            raise ExecutableCaptureTimeout(
                f"{label} executable capture exceeded "
                f"{EXECUTABLE_CAPTURE_SECONDS:g} seconds: {path}"
            )
        try:
            result = subprocess.run(
                [str(active_loader), option],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={"LC_ALL": "C"},
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise ExecutableCaptureTimeout(
                f"{label} executable capture exceeded "
                f"{EXECUTABLE_CAPTURE_SECONDS:g} seconds: {path}"
            ) from exc
        except OSError as exc:
            raise HarnessError(
                f"cannot query {label} ELF dynamic loader {option} for {path}: {exc}"
            ) from exc
        if (
            result.returncode != 0
            or len(result.stdout) > 1024 * 1024
            or len(result.stderr) > 1024 * 1024
        ):
            raise HarnessError(
                f"{label} ELF dynamic loader does not provide bounded glibc "
                f"{option} output: {path}"
            )
        return result

    diagnostics = loader_query("--list-diagnostics")
    values: dict[str, str] = {}
    try:
        output = diagnostics.stdout.decode("utf-8")
        for line in output.splitlines():
            key, separator, encoded = line.partition("=")
            if not separator:
                continue
            if key in {"dl_dst_lib", "dl_platform", "dl_hwcaps_subdirs"}:
                value = json.loads(encoded)
                if not isinstance(value, str):
                    raise ValueError("diagnostic is not a string")
                values[key] = value
            elif key == "dl_hwcaps_subdirs_active":
                values[key] = encoded
    except (UnicodeError, ValueError, json.JSONDecodeError) as exc:
        raise HarnessError(
            f"{label} ELF dynamic loader diagnostics are invalid: {path}"
        ) from exc
    library = values.get("dl_dst_lib", "")
    platform_value = values.get("dl_platform", "")
    for name, value in (("LIB", library), ("PLATFORM", platform_value)):
        if (
            not value
            or "$" in value
            or ":" in value
            or pathlib.PurePosixPath(value).is_absolute()
            or any(component in {"", ".", ".."} for component in value.split("/"))
        ):
            raise HarnessError(
                f"{label} ELF dynamic loader returned an unusable ${name} "
                f"value: {path}"
            )
    subdirs_value = values.get("dl_hwcaps_subdirs")
    active_value = values.get("dl_hwcaps_subdirs_active")
    if subdirs_value is None or active_value is None:
        raise HarnessError(
            f"{label} ELF dynamic loader did not report glibc-hwcaps priority: {path}"
        )
    subdirs = tuple(subdirs_value.split(":")) if subdirs_value else ()
    if (
        len(subdirs) > 64
        or len(set(subdirs)) != len(subdirs)
        or any(
            not name
            or name in {".", ".."}
            or "/" in name
            or "$" in name
            for name in subdirs
        )
    ):
        raise HarnessError(
            f"{label} ELF dynamic loader reported invalid glibc-hwcaps levels: {path}"
        )
    try:
        active_mask = int(active_value, 0)
    except ValueError as exc:
        raise HarnessError(
            f"{label} ELF dynamic loader reported an invalid glibc-hwcaps mask: {path}"
        ) from exc
    if active_mask < 0 or active_mask >> len(subdirs):
        raise HarnessError(
            f"{label} ELF dynamic loader reported an out-of-range glibc-hwcaps mask: {path}"
        )
    diagnostic_hwcaps = tuple(
        name for index, name in enumerate(subdirs) if active_mask & (1 << index)
    )

    help_output = loader_query("--help")
    try:
        help_lines = help_output.stdout.decode("utf-8").splitlines()
    except UnicodeError as exc:
        raise HarnessError(
            f"{label} ELF dynamic loader help is invalid: {path}"
        ) from exc
    heading = "Subdirectories of glibc-hwcaps directories, in priority order:"
    try:
        heading_index = help_lines.index(heading)
    except ValueError as exc:
        raise HarnessError(
            f"{label} ELF dynamic loader did not explain glibc-hwcaps priority: {path}"
        ) from exc
    searched_hwcaps: list[str] = []
    for line in help_lines[heading_index + 1 :]:
        if not line.startswith("  "):
            break
        name, separator, status_text = line.strip().partition(" (")
        if separator and status_text == "supported, searched)":
            searched_hwcaps.append(name)
    if tuple(searched_hwcaps) != diagnostic_hwcaps:
        raise HarnessError(
            f"{label} ELF dynamic loader reported inconsistent glibc-hwcaps priority: {path}"
        )
    tokens = DynamicLoaderTokens(library, platform_value, diagnostic_hwcaps)
    _DYNAMIC_LOADER_TOKEN_CACHE[cache_key] = tokens
    return tokens


def expand_elf_dynamic_tokens(
    entry: str,
    consumer_path: pathlib.Path,
    label: str,
    budget: ExecutableCaptureBudget,
    loader: DynamicLoaderContext | None,
    context: str,
) -> tuple[str, tuple[str, ...]]:
    """Expand the exact glibc dynamic-string token grammar used by the adapter."""
    pieces: list[str] = []
    names: list[str] = []
    malformed = False
    cursor = 0
    while cursor < len(entry):
        dollar = entry.find("$", cursor)
        if dollar < 0:
            pieces.append(entry[cursor:])
            break
        pieces.append(entry[cursor:dollar])
        if dollar + 1 >= len(entry):
            name = ""
            end = dollar + 1
            malformed = True
        elif entry[dollar + 1] == "{":
            close = entry.find("}", dollar + 2)
            if close < 0:
                name = entry[dollar + 2 :]
                end = len(entry)
                malformed = True
            else:
                name = entry[dollar + 2 : close]
                end = close + 1
                malformed = not name
        else:
            match = re.match(r"[A-Za-z0-9_]+", entry[dollar + 1 :])
            name = match.group(0) if match else ""
            end = dollar + 1 + len(name)
            malformed = malformed or not name
        names.append(name)
        pieces.append(f"\0{len(names) - 1}\0")
        cursor = end

    unsupported = sorted(
        {name or "<malformed>" for name in names}
        - {"ORIGIN", "LIB", "PLATFORM"}
    )
    if malformed and "<malformed>" not in unsupported:
        unsupported.append("<malformed>")
    if unsupported:
        raise HarnessError(
            f"{label} {context} contains unsupported ELF dynamic token(s) "
            f"{', '.join(unsupported)}: {consumer_path}"
        )
    runtime_tokens: DynamicLoaderTokens | None = None
    if any(name in {"LIB", "PLATFORM"} for name in names):
        if loader is None:
            raise HarnessError(
                f"{label} cannot resolve ELF dynamic tokens without a program "
                f"interpreter: {consumer_path}"
            )
        runtime_tokens = dynamic_loader_tokens(loader, consumer_path, label, budget)
    values = {
        "ORIGIN": str(consumer_path.parent),
        "LIB": runtime_tokens.library if runtime_tokens is not None else "",
        "PLATFORM": runtime_tokens.platform if runtime_tokens is not None else "",
    }
    expanded = "".join(pieces)
    for index, name in enumerate(names):
        expanded = expanded.replace(f"\0{index}\0", values[name])
    return expanded, tuple(names)


def elf_origin_searches_and_needed(
    image_fd: int,
    path: pathlib.Path,
    label: str,
    budget: ExecutableCaptureBudget,
    loader: DynamicLoaderContext | None = None,
) -> ElfDynamicSearch:
    """Read and expand the ELF dynamic-table subset used for origin capture."""
    size = os.fstat(image_fd).st_size
    if size < 16 or os.pread(image_fd, 4, 0) != b"\x7fELF":
        return ElfDynamicSearch((), (), (), loader, None)
    ident = os.pread(image_fd, 16, 0)
    elf_class, data_encoding = ident[4], ident[5]
    if elf_class not in (1, 2) or data_encoding not in (1, 2):
        raise HarnessError(f"{label} ELF identification is unsupported: {path}")
    endian = "<" if data_encoding == 1 else ">"
    header_format = endian + (
        "16sHHIIIIIHHHHHH" if elf_class == 1 else "16sHHIQQQIHHHHHH"
    )
    header_size = struct.calcsize(header_format)
    if size < header_size:
        raise HarnessError(f"{label} ELF header is truncated: {path}")
    header = struct.unpack(header_format, os.pread(image_fd, header_size, 0))
    phoff = header[5]
    phentsize = header[9]
    phnum = header[10]
    program_format = endian + ("IIIIIIII" if elf_class == 1 else "IIQQQQQQ")
    expected_phentsize = struct.calcsize(program_format)
    if phentsize < expected_phentsize or phnum > 4096:
        raise HarnessError(f"{label} ELF program headers are invalid: {path}")
    if phoff > size or phnum * phentsize > size - phoff:
        raise HarnessError(f"{label} ELF program headers are truncated: {path}")

    loads: list[tuple[int, int, int, int]] = []
    dynamic: tuple[int, int] | None = None
    interpreter: pathlib.Path | None = None
    for index in range(phnum):
        offset = phoff + index * phentsize
        fields = struct.unpack(
            program_format, os.pread(image_fd, expected_phentsize, offset)
        )
        if elf_class == 1:
            p_type, p_offset, p_vaddr, _, p_filesz, _, _, _ = fields
        else:
            p_type, _, p_offset, p_vaddr, _, p_filesz, _, _ = fields
        if p_offset > size or p_filesz > size - p_offset:
            raise HarnessError(f"{label} ELF segment is truncated: {path}")
        if p_type == 1:
            loads.append((p_vaddr, p_vaddr + p_filesz, p_offset, p_filesz))
        elif p_type == 2:
            dynamic = (p_offset, p_filesz)
        elif p_type == 3:
            interpreter_bytes = os.pread(image_fd, p_filesz, p_offset)
            if (
                len(interpreter_bytes) != p_filesz
                or not interpreter_bytes.endswith(b"\0")
                or b"\0" in interpreter_bytes[:-1]
            ):
                raise HarnessError(f"{label} ELF interpreter is invalid: {path}")
            try:
                interpreter = pathlib.Path(os.fsdecode(interpreter_bytes[:-1]))
            except UnicodeError as exc:
                raise HarnessError(
                    f"{label} ELF interpreter is invalid: {path}"
                ) from exc
            if not interpreter.is_absolute():
                raise HarnessError(f"{label} ELF interpreter is not absolute: {path}")
    if loader is None and interpreter is not None:
        loader = DynamicLoaderContext(interpreter)
    if dynamic is None:
        return ElfDynamicSearch((), (), (), loader, interpreter)

    dynamic_format = endian + ("iI" if elf_class == 1 else "qQ")
    dynamic_size = struct.calcsize(dynamic_format)
    if dynamic[1] // dynamic_size > 4096:
        raise HarnessError(f"{label} ELF dynamic table is too large: {path}")
    tags: dict[int, list[int]] = {}
    for offset in range(dynamic[0], dynamic[0] + dynamic[1], dynamic_size):
        if offset + dynamic_size > size:
            raise HarnessError(f"{label} ELF dynamic table is truncated: {path}")
        tag, value = struct.unpack(
            dynamic_format, os.pread(image_fd, dynamic_size, offset)
        )
        if tag == 0:
            break
        tags.setdefault(tag, []).append(value)
    if 5 not in tags or 10 not in tags:
        return ElfDynamicSearch((), (), (), loader, interpreter)
    strtab_address = tags[5][0]
    strtab_size = tags[10][0]
    strtab_offset: int | None = None
    for start, end, file_offset, _ in loads:
        if start <= strtab_address < end and strtab_size <= end - strtab_address:
            strtab_offset = file_offset + strtab_address - start
            break
    if strtab_offset is None or strtab_size > 16 * 1024 * 1024:
        raise HarnessError(f"{label} ELF string table is invalid: {path}")
    strings = os.pread(image_fd, strtab_size, strtab_offset)
    if len(strings) != strtab_size:
        raise HarnessError(f"{label} ELF string table is truncated: {path}")

    def dynamic_string(offset: int) -> str:
        if offset >= len(strings):
            raise HarnessError(f"{label} ELF dynamic string is invalid: {path}")
        end = strings.find(b"\0", offset)
        if end < 0:
            raise HarnessError(f"{label} ELF dynamic string is unterminated: {path}")
        try:
            return os.fsdecode(strings[offset:end])
        except UnicodeError as exc:
            raise HarnessError(f"{label} ELF dynamic string is invalid: {path}") from exc

    needed = tuple(dynamic_string(offset) for offset in tags.get(1, []))

    def expand_origin_entry(entry: str, tag_name: str) -> str:
        expanded, names = expand_elf_dynamic_tokens(
            entry, path, label, budget, loader, "origin search"
        )
        if "ORIGIN" not in names:
            raise HarnessError(
                f"{label} {tag_name} search entry cannot be sealed without "
                f"ORIGIN: {entry!r} in {path}"
            )
        return expanded

    def origin_searches(tag: int, tag_name: str) -> tuple[pathlib.Path, ...]:
        searches: list[pathlib.Path] = []
        if tag not in tags:
            return ()
        search_value = dynamic_string(tags[tag][0])
        for entry in search_value.split(":"):
            expanded = expand_origin_entry(entry, tag_name)
            candidate = pathlib.Path(os.path.abspath(expanded))
            if candidate not in searches:
                searches.append(candidate)
        return tuple(searches)

    runpath = origin_searches(29, "RUNPATH")
    # The loader ignores DT_RPATH when the same object has DT_RUNPATH.
    rpath = () if 29 in tags else origin_searches(15, "RPATH")
    return ElfDynamicSearch(rpath, runpath, needed, loader, interpreter)


def shebang_interpreter(
    prefix: bytes, path: pathlib.Path, label: str
) -> pathlib.Path | None:
    if not prefix.startswith(b"#!"):
        return None
    newline = prefix.find(b"\n", 2)
    if newline < 0:
        raise HarnessError(
            f"{label} shebang must end within {SHEBANG_PREFIX_BYTES} bytes: {path}"
        )
    directive = prefix[2:newline].strip(b" \t")
    if not directive or any(byte < 0x20 or byte == 0x7F for byte in directive):
        raise HarnessError(f"{label} shebang interpreter is invalid: {path}")
    if b" " in directive or b"\t" in directive:
        raise HarnessError(
            f"{label} shebang interpreter arguments are not supported: {path}"
        )
    interpreter = pathlib.Path(os.fsdecode(directive))
    if not interpreter.is_absolute():
        raise HarnessError(
            f"{label} shebang interpreter must be an absolute path: {path}"
        )
    return interpreter


def open_directory_authority(path: pathlib.Path) -> int:
    """Walk an absolute directory path without following any component."""
    if not path.is_absolute():
        raise OSError("directory authority path must be absolute")
    descriptor = os.open(
        pathlib.Path(path.anchor),
        os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
    )
    try:
        for component in path.parts[1:]:
            next_descriptor = os.open(
                component,
                os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW,
                dir_fd=descriptor,
            )
            os.close(descriptor)
            descriptor = next_descriptor
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def open_launch_anchor(path: pathlib.Path) -> int:
    """Retain the mount boundary that contained a captured absolute path."""
    anchor = path_namespace_anchor(path)
    return os.open(anchor, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC)


def resolve_search_dependency(
    directory: pathlib.Path,
    name: str,
    hwcaps: tuple[str, ...],
) -> tuple[pathlib.Path | None, pathlib.Path]:
    """Resolve one basename in the active loader's bounded hwcaps priority."""
    hwcaps_root = directory / "glibc-hwcaps"
    candidates = tuple(hwcaps_root / level / name for level in hwcaps) + (
        directory / name,
    )
    for candidate in candidates:
        try:
            if candidate.is_file():
                return pathlib.Path(os.path.abspath(candidate)), hwcaps_root
        except OSError:
            continue
    return None, hwcaps_root


def capture_origin_dependencies(
    image_fd: int,
    consumer_path: pathlib.Path,
    label: str,
    budget: ExecutableCaptureBudget,
    captured: dict[pathlib.Path, CapturedDependency],
    inherited_rpath: tuple[pathlib.Path, ...] = (),
    loader: DynamicLoaderContext | None = None,
) -> pathlib.Path | None:
    dynamic = elf_origin_searches_and_needed(
        image_fd, consumer_path, label, budget, loader
    )
    legacy_searches = tuple(
        dict.fromkeys((*dynamic.rpath, *inherited_rpath))
    )
    searches = tuple(dict.fromkeys((*legacy_searches, *dynamic.runpath)))
    for name in dynamic.needed:
        hwcaps_root: pathlib.Path | None = None
        if "/" in name:
            expanded, _ = expand_elf_dynamic_tokens(
                name,
                consumer_path,
                label,
                budget,
                dynamic.loader,
                "slash-bearing DT_NEEDED",
            )
            candidate = pathlib.Path(expanded)
            if not candidate.is_absolute():
                raise HarnessError(
                    f"{label} slash-bearing DT_NEEDED depends on the runtime "
                    f"working directory: {name!r} in {consumer_path}"
                )
            dependency_path = pathlib.Path(os.path.abspath(candidate))
            try:
                resolved_regular = dependency_path.is_file()
            except OSError as exc:
                raise HarnessError(
                    f"{label} cannot resolve slash-bearing DT_NEEDED {name!r} "
                    f"in {consumer_path}: {exc}"
                ) from exc
            if not resolved_regular:
                raise HarnessError(
                    f"{label} cannot resolve slash-bearing DT_NEEDED {name!r} "
                    f"in {consumer_path}"
                )
        else:
            dependency_path = None
            if searches:
                if dynamic.loader is None:
                    raise HarnessError(
                        f"{label} cannot establish glibc-hwcaps priority without "
                        f"a program interpreter: {consumer_path}"
                    )
                runtime_tokens = dynamic_loader_tokens(
                    dynamic.loader, consumer_path, label, budget
                )
                for directory in searches:
                    dependency_path, candidate_hwcaps_root = resolve_search_dependency(
                        directory, name, runtime_tokens.hwcaps
                    )
                    if dependency_path is not None:
                        hwcaps_root = candidate_hwcaps_root
                        break
        if dependency_path is None or dependency_path in captured:
            continue
        if len(captured) >= MAX_ORIGIN_DEPENDENCIES:
            raise HarnessError(
                f"{label} exceeds the {MAX_ORIGIN_DEPENDENCIES}-file "
                "origin dependency limit"
            )
        identity_fd = source_fd = dependency_fd = parent_fd = anchor_fd = -1
        dependency: CapturedDependency | None = None
        try:
            resolved = dependency_path.resolve(strict=True)
            parent_fd = open_directory_authority(dependency_path.parent)
            anchor_fd = open_launch_anchor(dependency_path)
            identity_fd = os.open(
                resolved, os.O_PATH | os.O_CLOEXEC | os.O_NOFOLLOW
            )
            identity = os.fstat(identity_fd)
            if not stat.S_ISREG(identity.st_mode):
                raise HarnessError(
                    f"{label} origin dependency is not a regular file: "
                    f"{dependency_path}"
                )
            if identity.st_size > budget.remaining_bytes:
                raise HarnessError(
                    f"{label} executable and origin dependencies exceed the "
                    f"{MAX_EXECUTABLE_CAPTURE_BYTES}-byte capture limit: "
                    f"{dependency_path}"
                )
            source_fd = os.open(
                f"/proc/self/fd/{identity_fd}",
                os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC,
            )
            info = os.fstat(source_fd)
            if (info.st_dev, info.st_ino) != (identity.st_dev, identity.st_ino):
                raise HarnessError(
                    f"{label} origin dependency identity changed during open: "
                    f"{dependency_path}"
                )
            flags = os.MFD_CLOEXEC | getattr(os, "MFD_ALLOW_SEALING", 0x0002)
            dependency_fd = os.memfd_create(f"shtest-{label}-dependency", flags)
            digest, _ = read_executable_source(
                source_fd, dependency_fd, dependency_path, label, budget
            )
            final_info = os.fstat(source_fd)
            if (final_info.st_dev, final_info.st_ino) != (
                identity.st_dev,
                identity.st_ino,
            ):
                raise HarnessError(
                    f"{label} origin dependency identity changed during capture: "
                    f"{dependency_path}"
                )
            os.fchmod(dependency_fd, 0o400)
            seals = (
                fcntl.F_SEAL_SEAL
                | fcntl.F_SEAL_SHRINK
                | fcntl.F_SEAL_GROW
                | fcntl.F_SEAL_WRITE
                | EXECUTABLE_MODE_SEAL
            )
            fcntl.fcntl(dependency_fd, fcntl.F_ADD_SEALS, seals)
            dependency = CapturedDependency(
                dependency_path,
                dependency_fd,
                digest,
                identity.st_dev,
                identity.st_ino,
                parent_fd,
                anchor_fd,
                hwcaps_root,
            )
            parent_fd = -1
            anchor_fd = -1
            dependency_fd = -1
            captured[dependency_path] = dependency
            capture_origin_dependencies(
                dependency.fd,
                dependency_path,
                label,
                budget,
                captured,
                legacy_searches,
                dynamic.loader,
            )
        except HarnessError:
            if dependency is not None:
                captured.pop(dependency.path, None)
                dependency.close()
            raise
        except OSError as exc:
            if dependency is not None:
                captured.pop(dependency.path, None)
                dependency.close()
            raise HarnessError(
                f"cannot snapshot {label} origin dependency "
                f"{dependency_path}: {exc}"
            ) from exc
        finally:
            for descriptor in (
                identity_fd,
                source_fd,
                dependency_fd,
                parent_fd,
                anchor_fd,
            ):
                if descriptor >= 0:
                    os.close(descriptor)
    return dynamic.program_interpreter


def capture_executable(
    path: pathlib.Path,
    label: str,
    *,
    allow_script: bool = True,
    capture_budget: ExecutableCaptureBudget | None = None,
) -> ExecutableImage:
    """Capture one executable tree under a single process-level deadline."""
    if capture_budget is not None:
        return _capture_executable(
            path,
            label,
            allow_script=allow_script,
            capture_budget=capture_budget,
        )
    budget = ExecutableCaptureBudget(
        time.monotonic() + EXECUTABLE_CAPTURE_SECONDS,
        MAX_EXECUTABLE_CAPTURE_BYTES,
    )
    with executable_capture_alarm(budget, path, label):
        return _capture_executable(
            path,
            label,
            allow_script=allow_script,
            capture_budget=budget,
        )


def _capture_executable(
    path: pathlib.Path,
    label: str,
    *,
    allow_script: bool = True,
    allow_elf_interpreter: bool = True,
    capture_budget: ExecutableCaptureBudget | None = None,
) -> ExecutableImage:
    """Capture a sealed master image that is never inherited by target code."""
    require_linux_process_primitives()
    identity_fd = -1
    source_fd = -1
    image_fd = -1
    parent_fd = anchor_fd = -1
    interpreter: ExecutableImage | None = None
    elf_interpreter: ExecutableImage | None = None
    dependencies: dict[pathlib.Path, CapturedDependency] = {}
    completed = False
    assert capture_budget is not None
    try:
        parent_fd = open_directory_authority(path.parent)
        anchor_fd = open_launch_anchor(path)
        identity_fd = os.open(
            path,
            os.O_PATH | os.O_CLOEXEC | os.O_NOFOLLOW,
        )
        identity = os.fstat(identity_fd)
        if stat.S_ISLNK(identity.st_mode):
            raise HarnessError(f"{label} executable must not be a symlink: {path}")
        if not stat.S_ISREG(identity.st_mode) or not identity.st_mode & 0o111:
            raise HarnessError(
                f"{label} executable is not an executable regular file: {path}"
            )
        if identity.st_size > capture_budget.remaining_bytes:
            raise HarnessError(
                f"{label} executable exceeds the {MAX_EXECUTABLE_CAPTURE_BYTES}-byte capture limit: {path}"
            )
        source_fd = os.open(
            f"/proc/self/fd/{identity_fd}",
            os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC,
        )
        info = os.fstat(source_fd)
        if (info.st_dev, info.st_ino) != (identity.st_dev, identity.st_ino):
            raise HarnessError(f"{label} executable identity changed during open: {path}")
        if not stat.S_ISREG(info.st_mode) or not info.st_mode & 0o111:
            raise HarnessError(
                f"{label} executable is not an executable regular file: {path}"
            )
        flags = os.MFD_CLOEXEC | getattr(os, "MFD_ALLOW_SEALING", 0x0002)
        image_fd = os.memfd_create(f"shtest-{label}", flags)
        digest, prefix = read_executable_source(
            source_fd, image_fd, path, label, capture_budget
        )
        final_info = os.fstat(source_fd)
        if (final_info.st_dev, final_info.st_ino) != (
            identity.st_dev,
            identity.st_ino,
        ):
            raise HarnessError(f"{label} executable identity changed during capture: {path}")
        os.fchmod(image_fd, 0o400)
        seals = (
            fcntl.F_SEAL_SEAL
            | fcntl.F_SEAL_SHRINK
            | fcntl.F_SEAL_GROW
            | fcntl.F_SEAL_WRITE
            | EXECUTABLE_MODE_SEAL
        )
        fcntl.fcntl(image_fd, fcntl.F_ADD_SEALS, seals)
        os.lseek(image_fd, 0, os.SEEK_SET)
        interpreter_path = shebang_interpreter(prefix, path, label)
        if interpreter_path is not None and not allow_script:
            raise HarnessError(
                f"{label} must be a native executable, not a shebang script: {path}"
            )
        if interpreter_path is not None:
            interpreter = _capture_executable(
                interpreter_path,
                f"{label} interpreter",
                allow_script=False,
                capture_budget=capture_budget,
            )
        else:
            elf_interpreter_path = capture_origin_dependencies(
                image_fd, path, label, capture_budget, dependencies
            )
            if elf_interpreter_path is not None:
                if not allow_elf_interpreter:
                    raise HarnessError(
                        f"{label} ELF program interpreter is recursively interpreted: "
                        f"{path}"
                    )
                elf_interpreter = _capture_executable(
                    elf_interpreter_path.resolve(strict=True),
                    f"{label} ELF interpreter",
                    allow_script=False,
                    allow_elf_interpreter=False,
                    capture_budget=capture_budget,
                )
                # Preserve the literal PT_INTERP pathname used by the kernel;
                # the captured source identity may be its resolved target.
                os.close(elf_interpreter.anchor_fd)
                elf_interpreter.anchor_fd = -1
                elf_interpreter.anchor_fd = open_launch_anchor(elf_interpreter_path)
                elf_interpreter.path = elf_interpreter_path
        image = ExecutableImage(
            path=path,
            label=label,
            fd=image_fd,
            sha256=digest,
            is_script=interpreter is not None,
            source_device=identity.st_dev,
            source_inode=identity.st_ino,
            parent_fd=parent_fd,
            anchor_fd=anchor_fd,
            interpreter=interpreter,
            elf_interpreter=elf_interpreter,
            origin_dependencies=tuple(dependencies.values()),
        )
        parent_fd = -1
        anchor_fd = -1
        completed = True
        return image
    except HarnessError:
        raise
    except OSError as exc:
        raise HarnessError(f"cannot snapshot {label} executable {path}: {exc}") from exc
    finally:
        if identity_fd >= 0:
            os.close(identity_fd)
        if source_fd >= 0:
            os.close(source_fd)
        if image_fd >= 0 and not completed:
            os.close(image_fd)
        if parent_fd >= 0:
            os.close(parent_fd)
        if anchor_fd >= 0:
            os.close(anchor_fd)
        if interpreter is not None and not completed:
            interpreter.close()
        if elf_interpreter is not None and not completed:
            elf_interpreter.close()
        if not completed:
            for dependency in dependencies.values():
                dependency.close()


def create_execution_image(
    executable: ExecutableImage | CapturedDependency,
    deadline: float,
    label: str | None = None,
) -> int:
    """Clone sealed bytes into a disposable executable memfd for one launch."""
    image_label = label or (
        executable.label
        if isinstance(executable, ExecutableImage)
        else "origin dependency"
    )
    flags = os.MFD_CLOEXEC | getattr(os, "MFD_ALLOW_SEALING", 0x0002)
    execution_fd = -1
    try:
        execution_fd = os.memfd_create(
            f"shtest-{image_label}-execution", flags
        )
        size = os.fstat(executable.fd).st_size
        offset = 0
        while offset < size:
            if time.monotonic() >= deadline:
                raise ProcessSetupError(
                    image_label,
                    "execution_image",
                    f"{image_label} process setup exceeded "
                    f"{PROCESS_SETUP_SECONDS:g} seconds during execution_image",
                    timed_out=True,
                )
            chunk = os.pread(executable.fd, min(1024 * 1024, size - offset), offset)
            if not chunk:
                raise OSError("captured executable image ended unexpectedly")
            view = memoryview(chunk)
            while view:
                written = os.write(execution_fd, view)
                view = view[written:]
            offset += len(chunk)
        os.fchmod(execution_fd, 0o500)
        seals = (
            fcntl.F_SEAL_SEAL
            | fcntl.F_SEAL_SHRINK
            | fcntl.F_SEAL_GROW
            | fcntl.F_SEAL_WRITE
            | EXECUTABLE_MODE_SEAL
        )
        fcntl.fcntl(execution_fd, fcntl.F_ADD_SEALS, seals)
        os.lseek(execution_fd, 0, os.SEEK_SET)
        result = execution_fd
        execution_fd = -1
        return result
    except ProcessSetupError:
        raise
    except OSError as exc:
        raise ProcessSetupError(
            image_label,
            "execution_image",
            f"cannot prepare disposable {image_label} execution image: {exc}",
            timed_out=False,
        ) from exc
    finally:
        if execution_fd >= 0:
            os.close(execution_fd)


def process_stat(pid: int) -> tuple[str, int, int] | None:
    try:
        value = pathlib.Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
        fields = value[value.rindex(")") + 2 :].split()
        return fields[0], int(fields[1]), int(fields[19])
    except (OSError, UnicodeError, ValueError, IndexError):
        return None


def process_identity(pid: int) -> tuple[int, int] | None:
    info = process_stat(pid)
    return None if info is None else (pid, info[2])


def process_group_identity(pid: int) -> ProcessGroupIdentity | None:
    """Capture session-leader metadata used to initiate bounded group cleanup."""
    try:
        value = pathlib.Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
        fields = value[value.rindex(")") + 2 :].split()
        return ProcessGroupIdentity(pid, int(fields[19]), int(fields[3]), int(fields[2]))
    except (OSError, UnicodeError, ValueError, IndexError):
        return None


def process_snapshot(budget: TraversalBudget) -> ProcessSnapshot:
    """Read a bounded process-table snapshot for all descendant searches."""
    children: dict[int, set[int]] = {}
    identities: dict[int, tuple[int, int]] = {}
    try:
        entries = os.scandir("/proc")
    except OSError:
        return ProcessSnapshot(children, identities, False)
    with entries:
        while True:
            if not budget.take_scan_entry():
                return ProcessSnapshot(children, identities, False)
            try:
                entry = next(entries)
            except StopIteration:
                return ProcessSnapshot(children, identities, True)
            if not entry.name.isdecimal():
                continue
            if not budget.take_identity_read():
                return ProcessSnapshot(children, identities, False)
            pid = int(entry.name)
            info = process_stat(pid)
            if info is not None:
                identities[pid] = (pid, info[2])
                children.setdefault(info[1], set()).add(pid)


def descendant_identities(
    roots: set[int], snapshot: ProcessSnapshot, budget: TraversalBudget
) -> DiscoveryResult:
    pending = sorted(roots, reverse=True)
    seen: set[int] = set()
    identities: set[tuple[int, int]] = set()
    while pending:
        if not budget.take_discovery():
            return DiscoveryResult(identities, False)
        pid = pending.pop()
        if pid in seen:
            continue
        seen.add(pid)
        identity = snapshot.identities.get(pid)
        if identity is None:
            continue
        identities.add(identity)
        pending.extend(sorted(snapshot.children.get(pid, ()), reverse=True))
    return DiscoveryResult(identities, True)


def descendant_baseline() -> set[tuple[int, int]]:
    deadline = time.monotonic() + PROCESS_CLEANUP_SECONDS
    budget = TraversalBudget(deadline)
    snapshot = process_snapshot(budget)
    result = descendant_identities(
        snapshot.children.get(os.getpid(), set()), snapshot, budget
    )
    if not snapshot.complete or not result.complete:
        raise HarnessError("cannot establish bounded child-process baseline")
    return result.identities


def signal_identity(identity: tuple[int, int]) -> bool:
    """SIGKILL exactly one validated Linux process identity through a pidfd."""
    pid, start_time = identity
    try:
        pidfd = os.pidfd_open(pid, 0)
    except (OSError, ValueError):
        return False
    try:
        # Opening first is essential: if PID reuse occurs before the open, this
        # check rejects the replacement; if it occurs afterward, the pidfd
        # remains bound to the process that was checked.
        if process_identity(pid) != (pid, start_time):
            return False
        signal.pidfd_send_signal(pidfd, signal.SIGKILL, None, 0)
        return True
    except (OSError, ValueError):
        return False
    finally:
        os.close(pidfd)


def signal_process_group(identity: ProcessGroupIdentity | None) -> bool:
    """Start group cleanup by identity-bound signaling of its original leader."""
    if identity is None:
        return False
    if (
        identity.session_id != identity.leader_pid
        or identity.process_group_id != identity.leader_pid
    ):
        return False
    # killpg(2) accepts only a numeric PGID and cannot be bound to a validated
    # leader lifetime. Kill the leader through its pidfd; the bounded process
    # table loop below pidfd-signals every discovered member and adopted child.
    return signal_identity((identity.leader_pid, identity.leader_start_time))


def identity_is_running(identity: tuple[int, int]) -> bool:
    pid, start_time = identity
    if process_identity(pid) != (pid, start_time):
        return False
    info = process_stat(pid)
    return info is not None and info[0] != "Z"


def reap_identities(
    identities: set[tuple[int, int]], leader_pid: int, deadline: float | None = None
) -> bool:
    for pid, start_time in sorted(identities):
        if deadline is not None and time.monotonic() >= deadline:
            return False
        if pid == leader_pid or process_identity(pid) != (pid, start_time):
            continue
        try:
            os.waitpid(pid, os.WNOHANG)
        except (ChildProcessError, ProcessLookupError):
            pass
    return True


def terminate_process_tree(
    process: subprocess.Popen[bytes] | ForkedProcess,
    baseline_children: set[tuple[int, int]],
    leader_identity: tuple[int, int] | None,
    leader_group: ProcessGroupIdentity | None,
    budget: TraversalBudget,
) -> ProcessTreeCleanupResult:
    """Kill escaped descendants and report cleanup evidence separately."""
    deadline = budget.deadline
    identity_captured = (
        leader_identity is not None and leader_identity[0] == process.pid
    )
    group_matches_leader = leader_group is None or (
        leader_identity is not None
        and (leader_group.leader_pid, leader_group.leader_start_time)
        == leader_identity
    )
    group_signaled = (
        identity_captured
        and group_matches_leader
        and time.monotonic() < deadline
        and signal_process_group(leader_group)
    )
    if not group_signaled and identity_captured:
        assert leader_identity is not None
        signal_identity(leader_identity)
    empty_rounds = 0
    observed: set[tuple[int, int]] = set()
    descendant_cleanup_required = False
    traversal_complete = identity_captured and group_matches_leader
    while time.monotonic() < deadline:
        process_terminated_for_cleanup(process)
        snapshot = process_snapshot(budget)
        direct_result = descendant_identities(
            snapshot.children.get(os.getpid(), set()), snapshot, budget
        )
        direct = direct_result.identities - baseline_children
        roots = {process.pid} if not process_terminated_for_cleanup(process) else set()
        root_result = descendant_identities(roots, snapshot, budget)
        retained_leader = (
            {leader_identity}
            if leader_identity is not None and leader_identity in direct
            else set()
        )
        current = (root_result.identities | direct) - retained_leader
        if current:
            descendant_cleanup_required = True
        discovery_complete = (
            snapshot.complete and direct_result.complete and root_result.complete
        )
        traversal_complete = traversal_complete and discovery_complete
        observed |= current
        for identity in sorted(current):
            if time.monotonic() >= deadline:
                traversal_complete = False
                break
            signal_identity(identity)
        if not reap_identities(observed, process.pid, deadline):
            traversal_complete = False
        live: set[tuple[int, int]] = set()
        for identity in sorted(observed):
            if time.monotonic() >= deadline:
                traversal_complete = False
                break
            if identity_is_running(identity):
                live.add(identity)
        if not discovery_complete:
            break
        leader_done = process_terminated_for_cleanup(process)
        if leader_done and not live and not current:
            empty_rounds += 1
            if empty_rounds >= 2:
                return ProcessTreeCleanupResult(
                    traversal_complete
                    and reap_identities(observed, process.pid, deadline),
                    descendant_cleanup_required,
                )
        else:
            empty_rounds = 0
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(0.01, remaining))
    if not reap_identities(observed, process.pid, deadline):
        traversal_complete = False
    if not traversal_complete or time.monotonic() >= deadline:
        return ProcessTreeCleanupResult(False, descendant_cleanup_required)
    return ProcessTreeCleanupResult(
        process_terminated_for_cleanup(process)
        and not any(identity_is_running(identity) for identity in observed),
        descendant_cleanup_required,
    )


def workspace_identity(descriptor: int) -> WorkspaceIdentity | None:
    try:
        info = os.fstat(descriptor)
    except OSError:
        return None
    mount_id = fd_mount_id(descriptor)
    if mount_id is None:
        return None
    return WorkspaceIdentity(info.st_dev, info.st_ino, mount_id)


def capture_workspace_authority(path: pathlib.Path) -> WorkspaceAuthority:
    """Pin the workspace and its strict search boundary before execution."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    parent_fd = -1
    root_fd = -1
    try:
        parent_fd = os.open(path.parent, flags)
        parent_identity = workspace_identity(parent_fd)
        if parent_identity is None:
            raise HarnessError(
                f"cannot read mount identity for quarantine parent {path.parent}"
            )
        root_fd = os.open(path.name, flags, dir_fd=parent_fd)
        identity = workspace_identity(root_fd)
        if identity is None:
            raise HarnessError(
                f"cannot read mount identity for quarantined workspace {path}"
            )
        if (
            identity.device != parent_identity.device
            or identity.mount_id != parent_identity.mount_id
        ):
            raise HarnessError(f"quarantined workspace crosses its parent mount: {path}")
        entry = os.stat(path.name, dir_fd=parent_fd, follow_symlinks=False)
        if (entry.st_dev, entry.st_ino) != (identity.device, identity.inode):
            raise HarnessError(f"quarantined workspace changed during capture: {path}")
        return WorkspaceAuthority(
            path, root_fd, parent_fd, identity, parent_identity
        )
    except HarnessError:
        if root_fd >= 0:
            os.close(root_fd)
        if parent_fd >= 0:
            os.close(parent_fd)
        raise
    except OSError as exc:
        if root_fd >= 0:
            os.close(root_fd)
        if parent_fd >= 0:
            os.close(parent_fd)
        raise HarnessError(f"cannot capture quarantined workspace {path}: {exc}") from exc


def capture_workspace_identity(path: pathlib.Path) -> WorkspaceIdentity:
    authority = capture_workspace_authority(path)
    try:
        return authority.identity
    finally:
        authority.close()


def identity_matches(info: os.stat_result, expected: WorkspaceIdentity) -> bool:
    return info.st_dev == expected.device and info.st_ino == expected.inode


def trusted_descriptor_path(descriptor: int) -> str | None:
    try:
        return os.readlink(f"/proc/self/fd/{descriptor}")
    except OSError:
        return None


def trusted_join(parent: str | None, parts: tuple[str, ...]) -> str | None:
    if parent is None:
        return None
    return os.path.join(parent, *parts)


def unlocated_workspace_reference(authority: WorkspaceAuthority) -> str:
    boundary = trusted_descriptor_path(authority.parent_fd) or str(authority.path.parent)
    identity = authority.identity
    return (
        f"{boundary}/<unlocated-shtest-quarantine "
        f"device={identity.device} inode={identity.inode} mount={identity.mount_id}>"
    )


def find_workspace_location(
    authority: WorkspaceAuthority, budget: TraversalBudget
) -> WorkspaceLocation | None:
    """Find the retained inode only beneath the retained parent descriptor."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    frames: list[tuple[int, Any]] = []
    try:
        if not budget.take_workspace_work():
            return None
        root = os.dup(authority.parent_fd)
        frames.append((root, os.scandir(root)))
        while frames:
            directory_fd, entries = frames[-1]
            try:
                if not budget.take_workspace_work():
                    return None
                entry = next(entries)
            except StopIteration:
                entries.close()
                os.close(directory_fd)
                frames.pop()
                continue
            except OSError:
                return None
            if not budget.take_workspace_work():
                return None
            try:
                info = os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            except OSError:
                return None
            if not budget.take_workspace_entry(info.st_size):
                return None
            if stat.S_ISDIR(info.st_mode) and identity_matches(
                info, authority.identity
            ):
                return WorkspaceLocation(os.dup(directory_fd), entry.name)
            if (
                not stat.S_ISDIR(info.st_mode)
                or info.st_dev != authority.parent_identity.device
            ):
                continue
            try:
                if not budget.take_workspace_work():
                    return None
                child_fd = os.open(entry.name, flags, dir_fd=directory_fd)
                child_info = os.fstat(child_fd)
                child_mount = workspace_identity(child_fd)
                if (
                    child_info.st_ino != info.st_ino
                    or child_mount is None
                    or child_mount.mount_id != authority.parent_identity.mount_id
                ):
                    os.close(child_fd)
                    continue
                frames.append((child_fd, os.scandir(child_fd)))
            except (FileNotFoundError, NotADirectoryError):
                continue
            except OSError:
                return None
        return None
    finally:
        for directory_fd, entries in reversed(frames):
            try:
                entries.close()
            except OSError:
                pass
            try:
                os.close(directory_fd)
            except OSError:
                pass


def rename_noreplace(
    old_parent_fd: int, old_name: str, new_parent_fd: int, new_name: str
) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        raise OSError(getattr(os, "ENOSYS", 38), "renameat2 is unavailable")
    renameat2.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    renameat2.restype = ctypes.c_int
    if renameat2(
        old_parent_fd,
        os.fsencode(old_name),
        new_parent_fd,
        os.fsencode(new_name),
        1,  # RENAME_NOREPLACE
    ) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def secure_workspace_location(
    authority: WorkspaceAuthority,
    location: WorkspaceLocation,
    budget: TraversalBudget,
) -> tuple[str, str] | None:
    """Atomically move a located entry, then verify which inode was moved."""
    boundary_path = trusted_descriptor_path(authority.parent_fd)
    for _ in range(4):
        if not budget.take_workspace_work():
            return None
        recovery_name = f".shtest-recovery-{os.getpid()}-{secrets.token_hex(8)}"
        try:
            rename_noreplace(
                location.parent_fd,
                location.name,
                authority.parent_fd,
                recovery_name,
            )
        except FileExistsError:
            continue
        except OSError:
            return None
        try:
            if not budget.take_workspace_work():
                return None
            info = os.stat(
                recovery_name,
                dir_fd=authority.parent_fd,
                follow_symlinks=False,
            )
        except OSError:
            return None
        if not stat.S_ISDIR(info.st_mode) or not identity_matches(
            info, authority.identity
        ):
            return None
        return recovery_name, trusted_join(boundary_path, (recovery_name,)) or recovery_name
    return None


def remove_verified_directory(
    parent_fd: int,
    name: str,
    directory_fd: int,
    expected: WorkspaceIdentity,
    budget: TraversalBudget,
) -> tuple[bool, str]:
    """Rename one entry, verify the moved inode, then remove only that inode."""
    removal_name = f".shtest-recovery-{os.getpid()}-{secrets.token_hex(8)}"
    if not budget.take_workspace_work():
        return False, name
    try:
        rename_noreplace(parent_fd, name, parent_fd, removal_name)
    except OSError:
        return False, name
    if not budget.take_workspace_work():
        return False, removal_name
    try:
        moved = os.stat(removal_name, dir_fd=parent_fd, follow_symlinks=False)
        retained = workspace_identity(directory_fd)
    except OSError:
        return False, removal_name
    if (
        retained != expected
        or not stat.S_ISDIR(moved.st_mode)
        or not identity_matches(moved, expected)
    ):
        return False, removal_name
    if not budget.take_workspace_work():
        return False, removal_name
    try:
        os.rmdir(removal_name, dir_fd=parent_fd)
        after = os.fstat(directory_fd)
    except OSError:
        return False, removal_name
    return after.st_nlink == 0, removal_name


def empty_retained_workspace(
    authority: WorkspaceAuthority, budget: TraversalBudget
) -> bool:
    """Empty exactly the retained directory inode without following links."""
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
    current = workspace_identity(authority.root_fd)
    if current != authority.identity or not budget.take_workspace_work():
        return False
    try:
        os.fchmod(authority.root_fd, 0o700)
        root_fd = os.dup(authority.root_fd)
        root_info = os.fstat(root_fd)
    except OSError:
        return False

    # Frames contain (fd, iterator, parent fd, name).  The retained root is
    # unlinked separately only after its inode identity is rechecked.
    frames: list[tuple[int, Any, int | None, str | None]] = []
    complete = True
    try:
        if not budget.take_workspace_work():
            os.close(root_fd)
            return False
        frames.append((root_fd, os.scandir(root_fd), None, None))
        while frames:
            if time.monotonic() >= budget.deadline:
                complete = False
                break
            directory_fd, entries, parent_fd, directory_name = frames[-1]
            try:
                if not budget.take_workspace_work():
                    complete = False
                    break
                entry = next(entries)
            except StopIteration:
                entries.close()
                frames.pop()
                if parent_fd is not None:
                    try:
                        child_identity = workspace_identity(directory_fd)
                        if child_identity is None:
                            complete = False
                        else:
                            removed, _ = remove_verified_directory(
                                parent_fd,
                                directory_name or "",
                                directory_fd,
                                child_identity,
                                budget,
                            )
                            if not removed:
                                complete = False
                    except OSError:
                        complete = False
                    finally:
                        os.close(directory_fd)
                    if not complete:
                        break
                else:
                    os.close(directory_fd)
                continue
            except OSError:
                complete = False
                break

            if not budget.take_workspace_work():
                complete = False
                break
            try:
                info = os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            except OSError:
                complete = False
                break
            if not budget.take_workspace_entry(info.st_size):
                complete = False
                break

            if stat.S_ISDIR(info.st_mode):
                if info.st_dev != root_info.st_dev or not budget.take_workspace_work():
                    complete = False
                    break
                try:
                    os.chmod(
                        entry.name,
                        stat.S_IMODE(info.st_mode) | 0o700,
                        dir_fd=directory_fd,
                        follow_symlinks=False,
                    )
                    child_fd = os.open(entry.name, directory_flags, dir_fd=directory_fd)
                    child_info = os.fstat(child_fd)
                    child_identity = workspace_identity(child_fd)
                    if (
                        child_info.st_ino != info.st_ino
                        or child_identity is None
                        or child_identity.mount_id != authority.identity.mount_id
                    ):
                        os.close(child_fd)
                        complete = False
                        break
                    frames.append(
                        (child_fd, os.scandir(child_fd), directory_fd, entry.name)
                    )
                except OSError:
                    complete = False
                    break
            else:
                try:
                    if not budget.take_workspace_work():
                        complete = False
                        break
                    os.unlink(entry.name, dir_fd=directory_fd)
                except FileNotFoundError:
                    pass
                except OSError:
                    complete = False
                    break
    finally:
        for directory_fd, entries, _, _ in reversed(frames):
            try:
                entries.close()
            except OSError:
                pass
            try:
                os.close(directory_fd)
            except OSError:
                pass
    return complete and time.monotonic() < budget.deadline


def cleanup_retained_workspace(
    authority: WorkspaceAuthority, budget: TraversalBudget
) -> WorkspaceCleanupResult:
    """Remove only the retained workspace inode within its retained boundary."""
    original_replaced = False
    try:
        original = os.stat(
            authority.path.name,
            dir_fd=authority.parent_fd,
            follow_symlinks=False,
        )
        original_replaced = not identity_matches(original, authority.identity)
    except FileNotFoundError:
        pass
    except OSError:
        original_replaced = True

    location: WorkspaceLocation | None = None
    if not original_replaced:
        try:
            current = os.stat(
                authority.path.name,
                dir_fd=authority.parent_fd,
                follow_symlinks=False,
            )
            if stat.S_ISDIR(current.st_mode) and identity_matches(
                current, authority.identity
            ):
                location = WorkspaceLocation(
                    os.dup(authority.parent_fd),
                    authority.path.name,
                )
        except OSError:
            pass
    if location is None:
        location = find_workspace_location(authority, budget)
    secured: tuple[str, str] | None = None
    if location is not None:
        try:
            secured = secure_workspace_location(authority, location, budget)
        finally:
            location.close()

    contents_complete = empty_retained_workspace(authority, budget)
    retained_reference = (
        secured[1]
        if secured is not None
        else unlocated_workspace_reference(authority)
    )
    if not contents_complete:
        return WorkspaceCleanupResult(False, retained_reference)

    if secured is None:
        if not budget.take_workspace_work():
            return WorkspaceCleanupResult(False, retained_reference)
        try:
            retained = os.fstat(authority.root_fd)
        except OSError:
            return WorkspaceCleanupResult(False, retained_reference)
        if retained.st_nlink != 0:
            return WorkspaceCleanupResult(False, retained_reference)
        if original_replaced:
            original_path = trusted_join(
                trusted_descriptor_path(authority.parent_fd),
                (authority.path.name,),
            )
            return WorkspaceCleanupResult(
                False, original_path or str(authority.path)
            )
        return WorkspaceCleanupResult(True, None)

    recovery_name, recovery_path = secured
    removed, retained_name = remove_verified_directory(
        authority.parent_fd,
        recovery_name,
        authority.root_fd,
        authority.identity,
        budget,
    )
    if not removed:
        boundary_path = trusted_descriptor_path(authority.parent_fd)
        retained_path = trusted_join(boundary_path, (retained_name,))
        return WorkspaceCleanupResult(False, retained_path or recovery_path)
    if original_replaced:
        original_path = trusted_join(
            trusted_descriptor_path(authority.parent_fd), (authority.path.name,)
        )
        return WorkspaceCleanupResult(False, original_path or str(authority.path))
    return WorkspaceCleanupResult(True, None)


def cleanup_quarantined_workspace(
    path: pathlib.Path,
    budget: TraversalBudget,
    expected: WorkspaceIdentity | None = None,
) -> bool:
    """Compatibility wrapper for cleanup callers that have a trusted path."""
    try:
        authority = capture_workspace_authority(path)
    except HarnessError:
        return expected is None and not path.exists()
    try:
        if expected is not None and authority.identity != expected:
            return False
        return cleanup_retained_workspace(authority, budget).complete
    finally:
        authority.close()


def fd_mount_id(fd: int) -> int | None:
    """Return Linux's mount identity for an already-open descriptor."""
    try:
        with open(f"/proc/self/fdinfo/{fd}", "r", encoding="ascii") as source:
            for line in source:
                if line.startswith("mnt_id:\t"):
                    return int(line.split()[1])
    except (OSError, UnicodeError, ValueError, IndexError):
        pass
    return None


def close_selector_file(selector: selectors.BaseSelector, file: Any) -> None:
    try:
        selector.unregister(file)
    except (KeyError, ValueError):
        pass
    if not file.closed:
        file.close()


def drain_emergency_output(
    process: subprocess.Popen[bytes] | ForkedProcess,
) -> tuple[bytes, bytes, bool, bool, bool]:
    """Bound partial-output recovery after a post-launch setup failure."""
    stdout = bytearray()
    stderr = bytearray()
    stdout_truncated = False
    stderr_truncated = False
    drain_timed_out = False
    selector = selectors.DefaultSelector()
    try:
        if process.stdin is not None and not process.stdin.closed:
            process.stdin.close()
        for pipe, stream in ((process.stdout, "stdout"), (process.stderr, "stderr")):
            if pipe is not None and not pipe.closed:
                os.set_blocking(pipe.fileno(), False)
                selector.register(pipe, selectors.EVENT_READ, stream)
        deadline = time.monotonic() + PIPE_DRAIN_SECONDS
        while selector.get_map():
            now = time.monotonic()
            if now >= deadline:
                drain_timed_out = True
                break
            for key, _ in selector.select(min(0.05, deadline - now)):
                pipe = key.fileobj
                try:
                    chunk = os.read(pipe.fileno(), READ_CHUNK_BYTES)
                except BlockingIOError:
                    continue
                if not chunk:
                    close_selector_file(selector, pipe)
                    continue
                target = stdout if key.data == "stdout" else stderr
                remaining = MAX_CAPTURE_BYTES - len(target)
                if remaining > 0:
                    target.extend(chunk[:remaining])
                if len(chunk) > remaining:
                    if key.data == "stdout":
                        stdout_truncated = True
                    else:
                        stderr_truncated = True
        return (
            bytes(stdout),
            bytes(stderr),
            stdout_truncated,
            stderr_truncated,
            drain_timed_out,
        )
    finally:
        for key in list(selector.get_map().values()):
            close_selector_file(selector, key.fileobj)
        selector.close()
        for pipe in (process.stdin, process.stdout, process.stderr):
            if pipe is not None and not pipe.closed:
                pipe.close()


class ForkedProcess:
    """A directly forked child whose wait status is exclusively owned here."""

    def __init__(
        self,
        pid: int,
        args: list[str],
        stdin: Any,
        stdout: Any,
        stderr: Any,
    ) -> None:
        self.pid = pid
        self.args = args
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
        self.returncode: int | None = None
        self._status_lost = False

    def _record_status(self, status: int) -> int:
        if os.WIFSIGNALED(status):
            self.returncode = -os.WTERMSIG(status)
        elif os.WIFEXITED(status):
            self.returncode = os.WEXITSTATUS(status)
        else:
            raise RuntimeError(f"unexpected child wait status: {status}")
        return self.returncode

    def poll(self) -> int | None:
        if self.returncode is not None:
            return self.returncode
        if self._status_lost:
            raise ProcessStatusError(self.pid, self.args)
        try:
            waited, status = os.waitpid(self.pid, os.WNOHANG)
        except ChildProcessError as exc:
            self._status_lost = True
            raise ProcessStatusError(self.pid, self.args) from exc
        if waited == 0:
            return None
        return self._record_status(status)

    def wait(self, timeout: float | None = None) -> int:
        if self.returncode is not None:
            return self.returncode
        if self._status_lost:
            raise ProcessStatusError(self.pid, self.args)
        if timeout is None:
            try:
                _, status = os.waitpid(self.pid, 0)
            except ChildProcessError as exc:
                self._status_lost = True
                raise ProcessStatusError(self.pid, self.args) from exc
            return self._record_status(status)
        deadline = time.monotonic() + timeout
        while True:
            result = self.poll()
            if result is not None:
                return result
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(self.args, timeout)
            time.sleep(min(0.002, remaining))


def process_terminated_for_cleanup(
    process: subprocess.Popen[bytes] | ForkedProcess,
) -> bool:
    """Treat a reaped child as dead while preserving status loss for callers."""
    try:
        return process.poll() is not None
    except ProcessStatusError:
        return True


def close_child_descriptors(keep: set[int]) -> None:
    """Close inherited runner descriptors in the setup child before untrusted work."""
    for name in os.listdir("/proc/self/fd"):
        try:
            descriptor = int(name)
        except ValueError:
            continue
        if descriptor in keep:
            continue
        try:
            os.close(descriptor)
        except OSError:
            pass


def write_child_setup_record(
    descriptor: int, kind: bytes, step: str, message: str = ""
) -> None:
    """Write one atomic framed stage/error record to the setup parent."""
    payload = kind + b"\0" + step.encode("ascii", errors="replace")
    if message:
        payload += b"\0" + message.encode("utf-8", errors="replace")
    payload = payload[:4000]
    frame = struct.pack("!H", len(payload)) + payload
    if os.write(descriptor, frame) != len(frame):
        raise OSError("short child setup status write")


def fork_tracked_process(
    launch_argv: list[str],
    launch_fd: int,
    pass_fds: tuple[int, ...],
    working_directory: pathlib.Path,
    path_launches: tuple[PathLaunch, ...],
    exec_path: pathlib.Path | None,
    path_launch_step: str,
) -> tuple[ForkedProcess, int]:
    """Fork a tracked native or shebang child and return its setup-status pipe."""
    stdin_read, stdin_write = os.pipe2(os.O_CLOEXEC)
    stdout_read, stdout_write = os.pipe2(os.O_CLOEXEC)
    stderr_read, stderr_write = os.pipe2(os.O_CLOEXEC)
    status_read, status_write = os.pipe2(os.O_CLOEXEC)
    descriptors = (
        stdin_read,
        stdin_write,
        stdout_read,
        stdout_write,
        stderr_read,
        stderr_write,
        status_read,
        status_write,
    )
    try:
        pid = os.fork()
    except BaseException:
        for descriptor in descriptors:
            os.close(descriptor)
        raise
    if pid == 0:
        step = "tracing"
        try:
            ptrace_linux(PTRACE_TRACEME)
            os.kill(os.getpid(), signal.SIGSTOP)
            step = "session_creation"
            write_child_setup_record(status_write, b"S", step)
            os.close(stdin_write)
            os.close(stdout_read)
            os.close(stderr_read)
            os.close(status_read)
            os.dup2(stdin_read, 0)
            os.dup2(stdout_write, 1)
            os.dup2(stderr_write, 2)
            keep = {0, 1, 2, status_write, *pass_fds}
            close_child_descriptors(keep)
            os.setsid()
            step = "chdir"
            write_child_setup_record(status_write, b"S", step)
            os.chdir(working_directory)
            if path_launches:
                step = path_launch_step
                write_child_setup_record(status_write, b"S", step)
                if (
                    step == "script_path_launch"
                    and len(path_launches) == 1
                    and len(path_launches[0].materials) == 1
                    and path_launches[0].anchor
                    == path_launches[0].materials[0].path.parent
                ):
                    material = path_launches[0].materials[0]
                    prepare_script_path_launch(
                        material.fd,
                        material.path,
                        material.parent_fd,
                        path_launches[0].staging_path,
                        material.sha256,
                    )
                else:
                    prepare_path_launches(path_launches)
            step = "descriptor_closure"
            write_child_setup_record(status_write, b"S", step)
            for descriptor in pass_fds:
                fcntl.fcntl(descriptor, fcntl.F_SETFD, fcntl.FD_CLOEXEC)
            step = "exec"
            write_child_setup_record(status_write, b"S", step)
            os.execve(
                (
                    str(exec_path)
                    if exec_path is not None
                    else f"/proc/self/fd/{launch_fd}"
                ),
                launch_argv,
                process_environment(working_directory),
            )
        except BaseException as exc:
            try:
                write_child_setup_record(
                    status_write, b"E", step, f"{type(exc).__name__}: {exc}"
                )
            except OSError:
                pass
            os._exit(127)
    os.close(stdin_read)
    os.close(stdout_write)
    os.close(stderr_write)
    os.close(status_write)
    process = ForkedProcess(
        pid,
        launch_argv,
        os.fdopen(stdin_write, "wb", buffering=0),
        os.fdopen(stdout_read, "rb", buffering=0),
        os.fdopen(stderr_read, "rb", buffering=0),
    )
    return process, status_read


def await_child_setup(
    process: ForkedProcess, status_fd: int, deadline: float
) -> ChildSetupOutcome:
    """Return failure, or the first parent timestamp of a kernel exec event."""
    payload = bytearray()
    current_step = "child_setup"
    trace_started = False
    status_open = True

    def consume_records() -> tuple[str, str] | None:
        nonlocal current_step
        while len(payload) >= 2:
            size = struct.unpack("!H", payload[:2])[0]
            if size == 0 or size > 4000:
                return "child_setup", "malformed child setup status record"
            if len(payload) < size + 2:
                return None
            record = bytes(payload[2 : size + 2])
            del payload[: size + 2]
            fields = record.split(b"\0", 2)
            if len(fields) < 2 or fields[0] not in (b"S", b"E"):
                return "child_setup", "malformed child setup status record"
            step = fields[1].decode("ascii", errors="replace")
            current_step = step
            if fields[0] == b"E":
                message = (
                    fields[2].decode("utf-8", errors="replace")
                    if len(fields) == 3
                    else "child setup failed without a message"
                )
                return step, message
        return None

    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError
        try:
            waited, wait_status = os.waitpid(
                process.pid, os.WNOHANG | os.WUNTRACED
            )
        except ChildProcessError as exc:
            process._status_lost = True
            raise ProcessStatusError(process.pid, process.args) from exc
        if waited:
            if os.WIFSTOPPED(wait_status):
                event = wait_status >> 16
                stopped_signal = os.WSTOPSIG(wait_status)
                if event == PTRACE_EVENT_EXEC:
                    execution_started = time.monotonic()
                    ptrace_linux(PTRACE_DETACH, process.pid)
                    if execution_started >= deadline:
                        raise TimeoutError
                    return ChildSetupOutcome(None, execution_started)
                if not trace_started and stopped_signal == signal.SIGSTOP:
                    ptrace_linux(
                        PTRACE_SETOPTIONS,
                        process.pid,
                        PTRACE_O_TRACEEXEC,
                    )
                    trace_started = True
                    ptrace_linux(PTRACE_CONT, process.pid)
                else:
                    ptrace_linux(PTRACE_CONT, process.pid, stopped_signal)
            else:
                process._record_status(wait_status)
                failure = consume_records()
                if failure is not None:
                    return ChildSetupOutcome(failure, None)
                if os.WIFEXITED(wait_status):
                    detail = (
                        "setup child exited with status "
                        f"{process.returncode} before exec"
                    )
                else:
                    detail = (
                        "setup child terminated by signal "
                        f"{-process.returncode} before exec"
                    )
                return ChildSetupOutcome((current_step, detail), None)
        if status_open:
            readable, _, _ = select.select(
                [status_fd], [], [], min(0.002, remaining)
            )
            if readable:
                chunk = os.read(status_fd, 4096)
                if chunk:
                    payload.extend(chunk)
                    failure = consume_records()
                    if failure is not None:
                        return ChildSetupOutcome(failure, None)
                else:
                    status_open = False
                    if payload:
                        failure = consume_records()
                        if failure is not None:
                            return ChildSetupOutcome(failure, None)
                        return ChildSetupOutcome(
                            ("child_setup", "truncated child setup status record"),
                            None,
                        )


def run_process(
    executable: ExecutableImage,
    arguments: tuple[str, ...] | list[str],
    stdin: bytes,
    timeout: float,
    temp_parent: pathlib.Path | None = None,
) -> ProcessResult:
    argv = [str(executable.path), *arguments]
    started = time.monotonic()
    setup_deadline = started + PROCESS_SETUP_SECONDS
    setup_step = "child_subreaper"
    setup_complete = False
    working_directory: pathlib.Path | None = None
    workspace_authority: WorkspaceAuthority | None = None
    process: subprocess.Popen[bytes] | ForkedProcess | None = None
    execution_fd = -1
    interpreter_execution_fd = -1
    elf_interpreter_execution_fd = -1
    extra_execution_fds: list[int] = []
    path_staging_paths: list[pathlib.Path] = []
    baseline_children: set[tuple[int, int]] = set()
    leader_identity: tuple[int, int] | None = None
    leader_group: ProcessGroupIdentity | None = None
    setup_status_fd = -1
    setup_alarm_active = False
    previous_alarm_handler: Any = None
    previous_alarm_timer = (0.0, 0.0)

    def require_setup_time(step: str) -> None:
        if time.monotonic() >= setup_deadline:
            raise ProcessSetupError(
                executable.label,
                step,
                f"{executable.label} process setup exceeded "
                f"{PROCESS_SETUP_SECONDS:g} seconds during {step}",
                timed_out=True,
            )

    def setup_timed_out(signum: int, frame: object) -> None:
        del signum, frame
        raise ProcessSetupError(
            executable.label,
            setup_step,
            f"{executable.label} process setup exceeded "
            f"{PROCESS_SETUP_SECONDS:g} seconds during {setup_step}",
            timed_out=True,
        )

    def arm_setup_alarm() -> None:
        nonlocal setup_alarm_active, previous_alarm_handler, previous_alarm_timer
        previous_alarm_handler = signal.getsignal(signal.SIGALRM)
        previous_alarm_timer = signal.getitimer(signal.ITIMER_REAL)
        if previous_alarm_timer != (0.0, 0.0):
            raise ProcessSetupError(
                executable.label,
                setup_step,
                f"cannot establish {executable.label} process setup deadline "
                "while the process already owns a real-time alarm",
                timed_out=False,
            )
        signal.signal(signal.SIGALRM, setup_timed_out)
        setup_alarm_active = True
        signal.setitimer(
            signal.ITIMER_REAL, max(0.000001, setup_deadline - time.monotonic())
        )

    def disarm_setup_alarm() -> None:
        nonlocal setup_alarm_active
        if not setup_alarm_active:
            return
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_alarm_handler)
        if previous_alarm_timer != (0.0, 0.0):
            signal.setitimer(signal.ITIMER_REAL, *previous_alarm_timer)
        setup_alarm_active = False

    try:
        enable_child_subreaper()
        require_setup_time(setup_step)
        arm_setup_alarm()
        setup_step = "workspace_creation"
        working_directory = pathlib.Path(
            tempfile.mkdtemp(prefix="shtest-quarantine-", dir=temp_parent)
        )
        require_setup_time(setup_step)
        setup_step = "workspace_authority"
        workspace_authority = capture_workspace_authority(working_directory)
        require_setup_time(setup_step)
        setup_step = "descendant_baseline"
        baseline_children = descendant_baseline()
        require_setup_time(setup_step)

        setup_step = "execution_image"
        execution_fd = create_execution_image(executable, setup_deadline)
        if executable.interpreter is not None:
            interpreter_execution_fd = create_execution_image(
                executable.interpreter, setup_deadline
            )
        native_program = executable.interpreter or executable
        native_program_execution_fd = (
            interpreter_execution_fd
            if executable.interpreter is not None
            else execution_fd
        )
        if native_program.elf_interpreter is not None:
            elf_interpreter_execution_fd = create_execution_image(
                native_program.elf_interpreter, setup_deadline
            )
        dependency_execution_fds: dict[pathlib.Path, int] = {}
        dependency_images = list(executable.origin_dependencies)
        if executable.interpreter is not None:
            dependency_images.extend(executable.interpreter.origin_dependencies)
        if native_program.elf_interpreter is not None:
            dependency_images.extend(
                native_program.elf_interpreter.origin_dependencies
            )
        for dependency in dependency_images:
            dependency_fd = create_execution_image(
                dependency, setup_deadline, executable.label
            )
            dependency_execution_fds[dependency.path] = dependency_fd
            extra_execution_fds.append(dependency_fd)
        require_setup_time(setup_step)

        launch_argv = argv
        launch_fd = execution_fd
        pass_fds = (execution_fd,)
        exec_path: pathlib.Path | None = None
        materials_by_launch: dict[pathlib.Path, dict[pathlib.Path, PathMaterial]] = {}
        authority_by_anchor: dict[pathlib.Path, int] = {}
        force_namespace_anchor = bool(
            executable.origin_dependencies
            or (
                executable.interpreter is not None
                and executable.interpreter.origin_dependencies
            )
            or (
                native_program.elf_interpreter is not None
                and native_program.elf_interpreter.origin_dependencies
            )
        )

        def add_material(material: PathMaterial) -> None:
            parent = material.path.parent
            try:
                authority_path = pathlib.Path(
                    os.readlink(f"/proc/self/fd/{material.parent_fd}")
                )
                if force_namespace_anchor or material.hwcaps_root is not None:
                    anchor = path_namespace_anchor(material.path)
                    directory_fd = material.anchor_fd
                    merged = materials_by_launch.setdefault(anchor, {})
                    authority_by_anchor.setdefault(anchor, directory_fd)
                    for existing_anchor in tuple(materials_by_launch):
                        if existing_anchor != anchor and existing_anchor.is_relative_to(
                            anchor
                        ):
                            for existing_path, existing_material in materials_by_launch.pop(
                                existing_anchor
                            ).items():
                                prior = merged.get(existing_path)
                                if (
                                    prior is not None
                                    and prior.sha256 != existing_material.sha256
                                ):
                                    raise ProcessSetupError(
                                        executable.label,
                                        "execution_image",
                                        f"conflicting captured path material for {existing_path}",
                                        timed_out=False,
                                    )
                                merged[existing_path] = existing_material
                            authority_by_anchor.pop(existing_anchor, None)
                elif authority_path == parent and not any(
                    material.path.is_relative_to(existing_anchor)
                    for existing_anchor in materials_by_launch
                ):
                    anchor = parent
                    directory_fd = material.parent_fd
                else:
                    anchor = path_namespace_anchor(material.path)
                    directory_fd = material.anchor_fd
                prior_authority = authority_by_anchor.setdefault(anchor, directory_fd)
                same_authority = os.path.samestat(
                    os.fstat(prior_authority), os.fstat(directory_fd)
                )
            except OSError as exc:
                raise ProcessSetupError(
                    executable.label,
                    "execution_image",
                    f"cannot validate captured path authority for {anchor}: {exc}",
                    timed_out=False,
                ) from exc
            if not same_authority:
                raise ProcessSetupError(
                    executable.label,
                    "execution_image",
                    f"conflicting captured path authority for {anchor}",
                    timed_out=False,
                )
            paths = materials_by_launch.setdefault(anchor, {})
            prior = paths.get(material.path)
            if prior is not None and prior.sha256 != material.sha256:
                raise ProcessSetupError(
                    executable.label,
                    "execution_image",
                    f"conflicting captured path material for {material.path}",
                    timed_out=False,
                )
            paths[material.path] = material

        if executable.origin_dependencies:
            exec_path = executable.path
            add_material(
                PathMaterial(
                    executable.path,
                    execution_fd,
                    executable.sha256,
                    True,
                    executable.parent_fd,
                    executable.anchor_fd,
                )
            )
            for dependency in executable.origin_dependencies:
                add_material(
                    PathMaterial(
                        dependency.path,
                        dependency_execution_fds[dependency.path],
                        dependency.sha256,
                        False,
                        dependency.parent_fd,
                        dependency.anchor_fd,
                        dependency.hwcaps_root,
                    )
                )

        if executable.interpreter is not None:
            launch_fd = interpreter_execution_fd
            launch_argv = [
                str(executable.interpreter.path),
                str(executable.path),
                *arguments,
            ]
            pass_fds = (
                execution_fd,
                interpreter_execution_fd,
            )
            add_material(
                PathMaterial(
                    executable.path,
                    execution_fd,
                    executable.sha256,
                    True,
                    executable.parent_fd,
                    executable.anchor_fd,
                )
            )
            if executable.interpreter.origin_dependencies:
                exec_path = executable.interpreter.path
                add_material(
                    PathMaterial(
                        executable.interpreter.path,
                        interpreter_execution_fd,
                        executable.interpreter.sha256,
                        True,
                        executable.interpreter.parent_fd,
                        executable.interpreter.anchor_fd,
                    )
                )
                for dependency in executable.interpreter.origin_dependencies:
                    add_material(
                        PathMaterial(
                            dependency.path,
                            dependency_execution_fds[dependency.path],
                            dependency.sha256,
                            False,
                            dependency.parent_fd,
                            dependency.anchor_fd,
                            dependency.hwcaps_root,
                        )
                    )
            require_setup_time(setup_step)

        if native_program.elf_interpreter is not None:
            native_loader = native_program.elf_interpreter
            launch_fd = elf_interpreter_execution_fd
            launch_argv = [
                str(native_loader.path),
                str(native_program.path),
                *(
                    [str(executable.path), *arguments]
                    if executable.interpreter is not None
                    else list(arguments)
                ),
            ]
            pass_fds = tuple(
                dict.fromkeys(
                    (
                        execution_fd,
                        native_program_execution_fd,
                        elf_interpreter_execution_fd,
                    )
                )
            )
            exec_path = native_loader.path
            add_material(
                PathMaterial(
                    native_program.path,
                    native_program_execution_fd,
                    native_program.sha256,
                    True,
                    native_program.parent_fd,
                    native_program.anchor_fd,
                )
            )
            add_material(
                PathMaterial(
                    native_loader.path,
                    elf_interpreter_execution_fd,
                    native_loader.sha256,
                    True,
                    native_loader.parent_fd,
                    native_loader.anchor_fd,
                )
            )
            for dependency in native_loader.origin_dependencies:
                add_material(
                    PathMaterial(
                        dependency.path,
                        dependency_execution_fds[dependency.path],
                        dependency.sha256,
                        False,
                        dependency.parent_fd,
                        dependency.anchor_fd,
                        dependency.hwcaps_root,
                    )
                )
            require_setup_time(setup_step)

        path_launches: list[PathLaunch] = []
        anchors = set(materials_by_launch)
        setup_step = "path_staging"
        for anchor, path_materials in materials_by_launch.items():
            staging_path = create_path_staging(anchors)
            path_staging_paths.append(staging_path)
            path_launches.append(
                PathLaunch(
                    anchor,
                    authority_by_anchor[anchor],
                    tuple(path_materials.values()),
                    staging_path,
                )
            )
        parent_authority_fds = [
            material.parent_fd
            for path_materials in materials_by_launch.values()
            for material in path_materials.values()
        ]
        launch_authority_fds = list(authority_by_anchor.values())
        pass_fds = tuple(
            dict.fromkeys(
                (
                    *pass_fds,
                    *extra_execution_fds,
                    *parent_authority_fds,
                    *launch_authority_fds,
                )
            )
        )
        path_launch_step = (
            "script_path_launch"
            if executable.interpreter is not None
            and not executable.interpreter.origin_dependencies
            else "origin_path_launch"
        )

        setup_step = "child_setup"
        # Parent-side preparation is complete. The direct child is published
        # immediately after fork, and the bounded status/ptrace handshake owns
        # native and shebang exec setup equally.
        disarm_setup_alarm()
        require_setup_time(setup_step)
        process, setup_status_fd = fork_tracked_process(
            launch_argv,
            launch_fd,
            pass_fds,
            working_directory,
            tuple(path_launches),
            exec_path,
            path_launch_step,
        )
        leader_identity = process_identity(process.pid)
        try:
            child_setup = await_child_setup(process, setup_status_fd, setup_deadline)
        except TimeoutError as exc:
            raise ProcessSetupError(
                executable.label,
                setup_step,
                f"{executable.label} process setup exceeded "
                f"{PROCESS_SETUP_SECONDS:g} seconds during {setup_step}",
                timed_out=True,
            ) from exc
        finally:
            os.close(setup_status_fd)
            setup_status_fd = -1
        if child_setup.failure is not None:
            child_step, child_message = child_setup.failure
            raise ProcessSetupError(
                executable.label,
                child_step,
                f"cannot execute {shlex.join(argv)} during {child_step}: "
                f"{child_message}",
                timed_out=False,
            )
        assert child_setup.execution_started is not None
        execution_deadline = execution_deadline_from_observation(
            child_setup.execution_started, timeout
        )
        for path_launch in path_launches:
            try:
                path_launch.staging_path.rmdir()
            except OSError as exc:
                raise ProcessSetupError(
                    executable.label,
                    setup_step,
                    f"cannot release private script staging path during "
                    f"process setup: {exc}",
                    timed_out=False,
                ) from exc
        os.close(execution_fd)
        execution_fd = -1
        if interpreter_execution_fd >= 0:
            os.close(interpreter_execution_fd)
            interpreter_execution_fd = -1
        if elf_interpreter_execution_fd >= 0:
            os.close(elf_interpreter_execution_fd)
            elf_interpreter_execution_fd = -1
        for descriptor in extra_execution_fds:
            os.close(descriptor)
        extra_execution_fds.clear()
        path_staging_paths.clear()
        disarm_setup_alarm()
        leader_identity = process_identity(process.pid)
        leader_group = process_group_identity(process.pid)
        setup_complete = True

        timed_out = False
        stdout_truncated = False
        stderr_truncated = False
        pipe_drain_timed_out = False
        cleanup_complete = True
        descendant_cleanup_required = False
        stdout = bytearray()
        stderr = bytearray()
        selector = selectors.DefaultSelector()
        assert process.stdin is not None
        assert process.stdout is not None
        assert process.stderr is not None
        for pipe in (process.stdin, process.stdout, process.stderr):
            os.set_blocking(pipe.fileno(), False)
        if stdin:
            selector.register(process.stdin, selectors.EVENT_WRITE, "stdin")
        else:
            process.stdin.close()
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        input_offset = 0
        drain_deadline: float | None = None
        cleanup_started = False
        cleanup_budget: TraversalBudget | None = None

        def begin_cleanup() -> None:
            nonlocal cleanup_started, cleanup_complete, descendant_cleanup_required
            nonlocal drain_deadline, cleanup_budget
            if cleanup_started:
                return
            cleanup_started = True
            if process.stdin is not None and not process.stdin.closed:
                close_selector_file(selector, process.stdin)
            cleanup_budget = TraversalBudget(
                time.monotonic() + PROCESS_CLEANUP_SECONDS
            )
            process_cleanup = terminate_process_tree(
                process,
                baseline_children,
                leader_identity,
                leader_group,
                cleanup_budget,
            )
            cleanup_complete = process_cleanup.complete
            descendant_cleanup_required = (
                process_cleanup.descendant_cleanup_required
            )
            drain_deadline = time.monotonic() + PIPE_DRAIN_SECONDS

        try:
            while True:
                now = time.monotonic()
                if not cleanup_started:
                    if execution_deadline_reached(now, execution_deadline):
                        timed_out = True
                        begin_cleanup()
                    elif process.poll() is not None:
                        begin_cleanup()
                output_open = any(
                    key.data in ("stdout", "stderr") for key in selector.get_map().values()
                )
                if cleanup_started and not output_open:
                    break
                if drain_deadline is not None and now >= drain_deadline:
                    if output_open:
                        pipe_drain_timed_out = True
                    for key in list(selector.get_map().values()):
                        if key.data in ("stdout", "stderr"):
                            close_selector_file(selector, key.fileobj)
                    break
                wait_until = execution_deadline if drain_deadline is None else drain_deadline
                wait = max(0.0, min(0.05, wait_until - now))
                for key, _ in selector.select(wait):
                    pipe = key.fileobj
                    if key.data == "stdin":
                        try:
                            written = os.write(pipe.fileno(), stdin[input_offset:])
                            input_offset += written
                        except BrokenPipeError:
                            input_offset = len(stdin)
                        if input_offset >= len(stdin):
                            close_selector_file(selector, pipe)
                        continue
                    try:
                        chunk = os.read(pipe.fileno(), READ_CHUNK_BYTES)
                    except BlockingIOError:
                        continue
                    if not chunk:
                        close_selector_file(selector, pipe)
                        continue
                    target = stdout if key.data == "stdout" else stderr
                    remaining = MAX_CAPTURE_BYTES - len(target)
                    if remaining > 0:
                        target.extend(chunk[:remaining])
                    if len(chunk) > remaining:
                        if key.data == "stdout":
                            stdout_truncated = True
                        else:
                            stderr_truncated = True
                        begin_cleanup()
        finally:
            selector.close()
            if not cleanup_started:
                begin_cleanup()
            assert cleanup_budget is not None
            try:
                process.wait(timeout=max(0.0, cleanup_budget.deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                cleanup_complete = False
                if leader_identity is not None:
                    signal_identity(leader_identity)
            for pipe in (process.stdin, process.stdout, process.stderr):
                if pipe is not None and not pipe.closed:
                    pipe.close()

        try:
            workspace_cleanup = cleanup_retained_workspace(
                workspace_authority, cleanup_budget
            )
        except Exception:
            workspace_cleanup = WorkspaceCleanupResult(
                False, unlocated_workspace_reference(workspace_authority)
            )
        cleanup_complete = cleanup_complete and workspace_cleanup.complete
        quarantined_path = workspace_cleanup.quarantined_path
        duration_ms = round((time.monotonic() - started) * 1000)
        returncode = process.returncode
        terminating_signal = (
            -returncode if returncode is not None and returncode < 0 else None
        )
        exit_status = (
            returncode if returncode is not None and returncode >= 0 else None
        )
        if timed_out:
            exit_status = None
            terminating_signal = None
        result = ProcessResult(
            argv=argv,
            working_directory=str(working_directory),
            exit_status=exit_status,
            signal=terminating_signal,
            timed_out=timed_out,
            duration_ms=duration_ms,
            stdout_b64=encoded(bytes(stdout)),
            stderr_b64=encoded(bytes(stderr)),
            stdout_truncated=stdout_truncated,
            stderr_truncated=stderr_truncated,
            output_limit_exceeded=stdout_truncated or stderr_truncated,
            pipe_drain_timed_out=pipe_drain_timed_out,
            descendant_cleanup_required=descendant_cleanup_required,
            cleanup_incomplete=not cleanup_complete,
            quarantined_path=quarantined_path,
        )
        workspace_authority.close()
        workspace_authority = None
        return result
    except BaseException as exc:
        # Never invoke TemporaryDirectory's implicit, unbounded recursive cleanup.
        disarm_setup_alarm()
        if setup_status_fd >= 0:
            os.close(setup_status_fd)
            setup_status_fd = -1
        if execution_fd >= 0:
            os.close(execution_fd)
            execution_fd = -1
        if interpreter_execution_fd >= 0:
            os.close(interpreter_execution_fd)
            interpreter_execution_fd = -1
        if elf_interpreter_execution_fd >= 0:
            os.close(elf_interpreter_execution_fd)
            elf_interpreter_execution_fd = -1
        for descriptor in extra_execution_fds:
            os.close(descriptor)
        extra_execution_fds.clear()
        for staging_path in path_staging_paths:
            try:
                staging_path.rmdir()
            except OSError:
                pass
        path_staging_paths.clear()
        process_emergency_budget = TraversalBudget(
            time.monotonic() + PROCESS_CLEANUP_SECONDS
        )
        process_cleanup = ProcessTreeCleanupResult(False, False)
        process_waited = process is None
        stdout = b""
        stderr = b""
        stdout_truncated = False
        stderr_truncated = False
        pipe_drain_timed_out = False
        if process is not None:
            try:
                if leader_identity is None:
                    leader_identity = process_identity(process.pid)
                if leader_group is None:
                    leader_group = process_group_identity(process.pid)
                process_cleanup = terminate_process_tree(
                    process,
                    baseline_children,
                    leader_identity,
                    leader_group,
                    process_emergency_budget,
                )
            except Exception:
                if leader_identity is not None:
                    signal_identity(leader_identity)
            try:
                try:
                    process.wait(
                        timeout=max(
                            0.0,
                            process_emergency_budget.deadline - time.monotonic(),
                        )
                    )
                    process_waited = True
                except subprocess.TimeoutExpired:
                    if leader_identity is not None:
                        signal_identity(leader_identity)
                    process.poll()
                except ProcessStatusError:
                    process_waited = True
            finally:
                (
                    stdout,
                    stderr,
                    stdout_truncated,
                    stderr_truncated,
                    pipe_drain_timed_out,
                ) = drain_emergency_output(process)
        workspace_emergency_budget = TraversalBudget(
            time.monotonic() + PROCESS_CLEANUP_SECONDS
        )
        workspace_cleanup = WorkspaceCleanupResult(
            working_directory is None, None
        )
        try:
            if workspace_authority is not None:
                workspace_cleanup = cleanup_retained_workspace(
                    workspace_authority, workspace_emergency_budget
                )
            elif working_directory is not None:
                workspace_complete = cleanup_quarantined_workspace(
                    working_directory, workspace_emergency_budget
                )
                workspace_cleanup = WorkspaceCleanupResult(
                    workspace_complete,
                    None if workspace_complete else str(working_directory),
                )
        except Exception:
            if workspace_authority is not None:
                quarantined_path = unlocated_workspace_reference(
                    workspace_authority
                )
            else:
                quarantined_path = (
                    None if working_directory is None else str(working_directory)
                )
            workspace_cleanup = WorkspaceCleanupResult(False, quarantined_path)
        if workspace_authority is not None:
            workspace_authority.close()
            workspace_authority = None
        emergency_result: ProcessResult | None = None
        if process is not None and working_directory is not None:
            returncode = process.returncode
            terminating_signal = (
                -returncode if returncode is not None and returncode < 0 else None
            )
            exit_status = (
                returncode if returncode is not None and returncode >= 0 else None
            )
            cleanup_complete = (
                process_cleanup.complete
                and process_waited
                and workspace_cleanup.complete
                and not pipe_drain_timed_out
            )
            emergency_result = ProcessResult(
                argv=argv,
                working_directory=str(working_directory),
                exit_status=exit_status,
                signal=terminating_signal,
                timed_out=False,
                duration_ms=round((time.monotonic() - started) * 1000),
                stdout_b64=encoded(stdout),
                stderr_b64=encoded(stderr),
                stdout_truncated=stdout_truncated,
                stderr_truncated=stderr_truncated,
                output_limit_exceeded=stdout_truncated or stderr_truncated,
                pipe_drain_timed_out=pipe_drain_timed_out,
                descendant_cleanup_required=(
                    process_cleanup.descendant_cleanup_required
                ),
                cleanup_incomplete=not cleanup_complete,
                quarantined_path=workspace_cleanup.quarantined_path,
            )
        if (
            not setup_complete
            and isinstance(exc, Exception)
            and not isinstance(exc, ProcessSetupError)
        ):
            raise ProcessSetupError(
                executable.label,
                setup_step,
                f"{executable.label} process setup failed during {setup_step}: {exc}",
                timed_out=False,
                result=emergency_result,
            ) from exc
        if isinstance(exc, ProcessSetupError) and emergency_result is not None:
            exc.result = emergency_result
        if isinstance(exc, ProcessStatusError):
            exc.role = executable.label
            exc.result = emergency_result
        raise


def version_of(
    executable: ExecutableImage, timeout: float, role: str
) -> tuple[str, ProcessResult]:
    result = run_process(executable, ["--version"], b"", timeout)
    stdout = base64.b64decode(result.stdout_b64)
    stderr = base64.b64decode(result.stderr_b64)
    if result.timed_out:
        raise VersionProbeError(f"{executable.path} --version timed out", role, result)
    if result.output_limit_exceeded:
        raise VersionProbeError(
            f"{executable.path} --version exceeded the output capture limit", role, result
        )
    if (
        result.pipe_drain_timed_out
        or result.descendant_cleanup_required
        or result.cleanup_incomplete
    ):
        raise VersionProbeError(
            f"{executable.path} --version did not cleanly release its processes and pipes",
            role,
            result,
        )
    if (
        result.exit_status != 0
        or result.signal is not None
        or stderr
        or not stdout.endswith(b"\n")
        or stdout.count(b"\n") != 1
    ):
        raise VersionProbeError(
            f"{role} --version must succeed with one clean LF-terminated stdout line",
            role,
            result,
        )
    try:
        version = stdout[:-1].decode("utf-8")
    except UnicodeDecodeError as exc:
        raise VersionProbeError(
            f"{executable.path} --version is not UTF-8", role, result
        ) from exc
    if not version:
        raise VersionProbeError(
            f"{role} --version must identify the executable", role, result
        )
    return version, result


def require_containment(
    result: ProcessResult, role: str, invocation: str
) -> None:
    """Fail-stop before a survivor can enter any later process baseline."""
    if result.cleanup_incomplete:
        detail = ""
        if result.quarantined_path is not None:
            detail = f"; retained quarantine: {result.quarantined_path}"
        raise ContainmentError(
            f"{role} {invocation} lost process/workspace containment{detail}",
            role,
            result,
        )


def compare_results(oracle: ProcessResult, candidate: ProcessResult) -> list[str]:
    differences: list[str] = []
    if candidate.output_limit_exceeded:
        differences.append("candidate hit the output capture resource limit")
    if candidate.stdout_truncated:
        differences.append(
            f"candidate stdout exceeded {MAX_CAPTURE_BYTES}-byte capture limit"
        )
    if candidate.stderr_truncated:
        differences.append(
            f"candidate stderr exceeded {MAX_CAPTURE_BYTES}-byte capture limit"
        )
    if candidate.pipe_drain_timed_out:
        differences.append("candidate pipes were forcibly closed after drain deadline")
    if candidate.cleanup_incomplete:
        differences.append("candidate process-tree cleanup was incomplete")
    if oracle.descendant_cleanup_required != candidate.descendant_cleanup_required:
        differences.append(
            "descendant cleanup requirement differs: "
            f"oracle={oracle.descendant_cleanup_required}, "
            f"candidate={candidate.descendant_cleanup_required}"
        )
    if oracle.timed_out != candidate.timed_out:
        differences.append(
            f"timeout differs: oracle={oracle.timed_out}, candidate={candidate.timed_out}"
        )
    if oracle.exit_status != candidate.exit_status:
        differences.append(
            "exit status differs: "
            f"oracle={oracle.exit_status}, candidate={candidate.exit_status}"
        )
    if oracle.signal != candidate.signal:
        differences.append(
            f"signal differs: oracle={oracle.signal}, candidate={candidate.signal}"
        )
    if oracle.stdout_b64 != candidate.stdout_b64:
        differences.append("stdout bytes differ")
    if oracle.stderr_b64 != candidate.stderr_b64:
        differences.append("stderr bytes differ")
    return differences


def oracle_result_error(result: ProcessResult) -> str | None:
    if result.timed_out:
        return "oracle timed out"
    exceeded = []
    if result.stdout_truncated:
        exceeded.append("stdout")
    if result.stderr_truncated:
        exceeded.append("stderr")
    if exceeded:
        return (
            f"oracle {' and '.join(exceeded)} exceeded "
            f"{MAX_CAPTURE_BYTES}-byte capture limit"
        )
    if result.pipe_drain_timed_out:
        return "oracle pipes were forcibly closed after drain deadline"
    if result.cleanup_incomplete:
        return "oracle process-tree cleanup was incomplete"
    return None


def case_record(case: ProcessCase) -> dict[str, Any]:
    result: dict[str, Any] = {
        "ordinal": case.ordinal,
        "id": case.case_id,
        "kind": case.kind,
        "provenance": asdict(case.provenance),
    }
    if case.kind == "run":
        result.update(
            {
                "argv": list(case.argv or ()),
                "stdin_b64": encoded(case.stdin or b""),
                "timeout_seconds": case.timeout_seconds,
                "comparison_mode": "exact-process",
            }
        )
    else:
        result["reason"] = case.skip_reason
    return result


def write_report(path: pathlib.Path | None, report: dict[str, Any]) -> None:
    if path is None:
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except OSError as exc:
        raise HarnessError(f"cannot write report {path}: {exc}") from exc


def parse_args(argv: list[str]) -> argparse.Namespace:
    root = repository_root()
    parser = argparse.ArgumentParser(
        description="Compare explicit jq shtest process cases exactly."
    )
    parser.add_argument("--catalog", type=pathlib.Path, default=root / "compat/shtest-process.json")
    parser.add_argument("--oracle", type=pathlib.Path)
    parser.add_argument("--candidate", type=pathlib.Path)
    parser.add_argument("--case", action="append", default=[], dest="patterns")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--json-report", type=pathlib.Path)
    parser.add_argument("--show-passes", action="store_true")
    parser.add_argument("--allow-unpinned-oracle", action="store_true")
    args = parser.parse_args(argv)
    if not args.list and (args.oracle is None or args.candidate is None):
        parser.error("--oracle and --candidate are required unless --list is used")
    return args


def executable_report(
    path: pathlib.Path,
    image: ExecutableImage | None,
    version: str | None,
    version_result: ProcessResult | None,
) -> dict[str, Any]:
    interpreter = (
        image.interpreter if isinstance(image, ExecutableImage) else None
    )

    def dependency_reports(
        dependencies: tuple[CapturedDependency | ExecutableImage, ...],
    ) -> list[dict[str, Any]]:
        return [
            {
                "path": str(dependency.path),
                "sha256": dependency.sha256,
                "source_device": dependency.source_device,
                "source_inode": dependency.source_inode,
            }
            for dependency in sorted(dependencies, key=lambda item: str(item.path))
        ]

    def execution_dependencies(
        executable: ExecutableImage,
    ) -> tuple[CapturedDependency | ExecutableImage, ...]:
        dependencies: list[CapturedDependency | ExecutableImage] = list(
            executable.origin_dependencies
        )
        if executable.elf_interpreter is not None:
            dependencies.append(executable.elf_interpreter)
            dependencies.extend(executable.elf_interpreter.origin_dependencies)
        return tuple(dependencies)

    return {
        "path": str(path),
        "version": version,
        "sha256": None if image is None else image.sha256,
        "source_device": None if image is None else image.source_device,
        "source_inode": None if image is None else image.source_inode,
        "dependencies": (
            dependency_reports(execution_dependencies(image))
            if isinstance(image, ExecutableImage)
            else []
        ),
        "interpreter": (
            None
            if interpreter is None
            else {
                "path": str(interpreter.path),
                "sha256": interpreter.sha256,
                "source_device": interpreter.source_device,
                "source_inode": interpreter.source_inode,
                "dependencies": dependency_reports(
                    execution_dependencies(interpreter)
                ),
            }
        ),
        "version_process": None if version_result is None else asdict(version_result),
    }


def report_document(
    *,
    catalog: pathlib.Path,
    patterns: list[str],
    oracle_path: pathlib.Path,
    candidate_path: pathlib.Path,
    oracle: ExecutableImage | None,
    candidate: ExecutableImage | None,
    oracle_version: str | None,
    candidate_version: str | None,
    oracle_version_result: ProcessResult | None,
    candidate_version_result: ProcessResult | None,
    summary: dict[str, int],
    results: list[dict[str, Any]],
    startup_failure: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "catalog": str(catalog),
        "comparison_mode": (
            "exact stdout bytes, stderr bytes, exit status, signal, timeout, "
            "and descendant-cleanup evidence"
        ),
        "resource_limits": {
            "capture_bytes_per_stream": MAX_CAPTURE_BYTES,
            "pipe_drain_seconds": PIPE_DRAIN_SECONDS,
            "process_cleanup_seconds": PROCESS_CLEANUP_SECONDS,
            "process_scan_entry_budget": PROCESS_SCAN_ENTRY_BUDGET,
            "process_identity_read_budget": PROCESS_IDENTITY_READ_BUDGET,
            "process_discovery_budget": PROCESS_DISCOVERY_BUDGET,
            "workspace_cleanup_entry_budget": WORKSPACE_CLEANUP_ENTRY_BUDGET,
            "workspace_cleanup_byte_budget": WORKSPACE_CLEANUP_BYTE_BUDGET,
            "workspace_cleanup_work_budget": WORKSPACE_CLEANUP_WORK_BUDGET,
            "executable_capture_seconds": EXECUTABLE_CAPTURE_SECONDS,
            "executable_capture_bytes": MAX_EXECUTABLE_CAPTURE_BYTES,
        },
        "environment": {
            "inherits_host_environment": False,
            "per_process_isolated_working_directory": True,
            "keys": sorted(process_environment(pathlib.Path("WORKING_DIRECTORY"))),
        },
        "platform": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "python": platform.python_version(),
        },
        "executable_identity": (
            "sha256 of sealed master bytes cloned into each disposable execution image"
        ),
        "oracle": executable_report(
            oracle_path, oracle, oracle_version, oracle_version_result
        ),
        "candidate": executable_report(
            candidate_path, candidate, candidate_version, candidate_version_result
        ),
        "selection": {"patterns": patterns},
        "summary": summary,
        "cases": results,
        "startup_failure": startup_failure,
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    report_path = args.json_report.resolve() if args.json_report else None
    catalog = args.catalog.resolve()
    selected: list[ProcessCase] = []
    oracle_path = (
        absolute_unresolved(args.oracle) if args.oracle is not None else pathlib.Path("")
    )
    candidate_path = (
        absolute_unresolved(args.candidate)
        if args.candidate is not None
        else pathlib.Path("")
    )
    oracle: ExecutableImage | None = None
    candidate: ExecutableImage | None = None
    oracle_version: str | None = None
    candidate_version: str | None = None
    oracle_version_result: ProcessResult | None = None
    candidate_version_result: ProcessResult | None = None
    results: list[dict[str, Any]] = []
    passed = failed = skipped = errors = 0
    stage = "catalog"
    role: str | None = None
    try:
        selected = select_cases(load_catalog(catalog), args.patterns)
        if not selected:
            raise HarnessError("selection contains no catalog cases")
        if args.list:
            for case in selected:
                detail = case.skip_reason if case.kind == "skip" else shlex.join(case.argv or ())
                print(f"{case.case_id}\t{case.kind}\t{case.provenance.source}:{case.provenance.line_start}-{case.provenance.line_end}\t{detail}")
            return 0

        stage, role = "executable_capture", "oracle"
        oracle = capture_executable(oracle_path, "oracle")
        stage, role = "executable_capture", "candidate"
        candidate = capture_executable(candidate_path, "candidate")

        stage, role = "version_probe", "oracle"
        try:
            oracle_version, oracle_version_result = version_of(oracle, 5.0, "oracle")
        except VersionProbeError as exc:
            oracle_version_result = exc.result
            raise
        stage = "version_identity"
        if (
            not args.allow_unpinned_oracle
            and oracle_version != EXPECTED_ORACLE_VERSION
        ):
            raise HarnessError(
                f"oracle reports {oracle_version!r}; expected {EXPECTED_ORACLE_VERSION!r}"
            )

        oracle_results: dict[str, ProcessResult] = {}
        oracle_errors: dict[str, str] = {}
        stage, role = "oracle_case_execution", "oracle"
        for case in selected:
            if case.kind == "skip":
                continue
            result = run_process(
                oracle, case.argv or (), case.stdin or b"", case.timeout_seconds or 0
            )
            require_containment(result, "oracle", f"case {case.case_id}")
            oracle_results[case.case_id] = result
            problem = oracle_result_error(result)
            if problem is not None:
                oracle_errors[case.case_id] = problem

        stage, role = "version_probe", "candidate"
        try:
            candidate_version, candidate_version_result = version_of(
                candidate, 5.0, "candidate"
            )
        except VersionProbeError as exc:
            candidate_version_result = exc.result
            raise
        stage = "version_identity"
        if candidate_version != oracle_version:
            raise HarnessError(
                f"candidate reports {candidate_version!r}; "
                f"expected oracle identity {oracle_version!r}"
            )

        stage, role = "case_execution", "candidate"
        for case in selected:
            record = case_record(case)
            if case.kind == "skip":
                skipped += 1
                print(f"SKIP {case.case_id}: {case.skip_reason}")
                results.append(
                    {"case": record, "status": "skip", "reason": case.skip_reason}
                )
                continue
            oracle_result = oracle_results[case.case_id]
            if case.case_id in oracle_errors:
                errors += 1
                problem = oracle_errors[case.case_id]
                print(f"ERROR {case.case_id}: {problem}")
                results.append(
                    {
                        "case": record,
                        "status": "error",
                        "differences": [problem],
                        "oracle": asdict(oracle_result),
                    }
                )
                continue
            candidate_result = run_process(
                candidate, case.argv or (), case.stdin or b"", case.timeout_seconds or 0
            )
            require_containment(
                candidate_result, "candidate", f"case {case.case_id}"
            )
            differences = compare_results(oracle_result, candidate_result)
            status = "pass" if not differences else "fail"
            if status == "pass":
                passed += 1
                if args.show_passes:
                    print(f"PASS {case.case_id}")
            else:
                failed += 1
                print(f"FAIL {case.case_id}")
                for difference in differences:
                    print(f"  - {difference}")
            results.append(
                {
                    "case": record,
                    "status": status,
                    "differences": differences,
                    "oracle": asdict(oracle_result),
                    "candidate": asdict(candidate_result),
                }
            )

        summary = {
            "selected": len(selected),
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "errors": errors,
        }
        report = report_document(
            catalog=catalog,
            patterns=args.patterns,
            oracle_path=oracle_path,
            candidate_path=candidate_path,
            oracle=oracle,
            candidate=candidate,
            oracle_version=oracle_version,
            candidate_version=candidate_version,
            oracle_version_result=oracle_version_result,
            candidate_version_result=candidate_version_result,
            summary=summary,
            results=results,
            startup_failure=None,
        )
        write_report(report_path, report)
        print(
            f"SUMMARY selected={len(selected)} passed={passed} failed={failed} "
            f"skipped={skipped} errors={errors}"
        )
        if errors:
            return 2
        return 1 if failed else 0
    except HarnessError as exc:
        if not args.list and (selected or stage == "catalog"):
            if isinstance(exc, ProcessSetupError):
                stage = exc.report_stage
                role = exc.role
            if isinstance(exc, (VersionProbeError, ContainmentError)):
                role = exc.role
            if isinstance(exc, ProcessStatusError):
                role = exc.role
            failure_result = (
                exc.result
                if isinstance(
                    exc,
                    (
                        ProcessSetupError,
                        ProcessStatusError,
                        VersionProbeError,
                        ContainmentError,
                    ),
                )
                else None
            )
            startup_failure = {
                "stage": stage,
                "role": role,
                "message": str(exc),
                "process_result": (
                    None if failure_result is None else asdict(failure_result)
                ),
            }
            failure_report = report_document(
                catalog=catalog,
                patterns=args.patterns,
                oracle_path=oracle_path,
                candidate_path=candidate_path,
                oracle=oracle,
                candidate=candidate,
                oracle_version=oracle_version,
                candidate_version=candidate_version,
                oracle_version_result=oracle_version_result,
                candidate_version_result=candidate_version_result,
                summary={
                    "selected": len(selected),
                    "passed": passed,
                    "failed": failed,
                    "skipped": skipped,
                    "errors": errors + 1,
                },
                results=results,
                startup_failure=startup_failure,
            )
            try:
                write_report(report_path, failure_report)
            except HarnessError as report_exc:
                print(f"HARNESS ERROR: {report_exc}", file=sys.stderr)
        print(f"HARNESS ERROR: {exc}", file=sys.stderr)
        return 2
    finally:
        if candidate is not None:
            candidate.close()
        if oracle is not None:
            oracle.close()


if __name__ == "__main__":
    raise SystemExit(main())
