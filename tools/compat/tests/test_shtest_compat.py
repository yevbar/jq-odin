#!/usr/bin/env python3

from __future__ import annotations

import base64
import ctypes
import hashlib
import importlib.util
import json
import os
import pathlib
import select
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[3]
RUNNER = ROOT / "tools/compat/shtest_compat.py"
SPEC = importlib.util.spec_from_file_location("shtest_compat", RUNNER)
assert SPEC is not None and SPEC.loader is not None
SHTEST = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SHTEST
SPEC.loader.exec_module(SHTEST)


FAKE_CLI = r'''#!{interpreter}
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import time

MODE = {mode!r}
TARGET = {target!r}

if sys.argv[1:] == ["--version"]:
    if MODE == "clobber":
        shutil.copyfile(sys.argv[0], TARGET)
        os.chmod(TARGET, 0o755)
    elif MODE == "self-replace":
        replacement = pathlib.Path(TARGET + ".replacement")
        replacement.write_text(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "sys.stdout.buffer.write(b'replaced-by-version')\n",
            encoding="utf-8",
        )
        replacement.chmod(0o755)
        os.replace(replacement, TARGET)
    elif MODE == "version-nonzero":
        sys.stdout.write({version!r} + "\n")
        raise SystemExit(7)
    elif MODE == "version-signal":
        os.kill(os.getpid(), signal.SIGTERM)
    elif MODE == "version-timeout":
        time.sleep(60)
    elif MODE == "version-no-newline":
        sys.stdout.write({version!r})
        raise SystemExit(0)
    elif MODE == "version-multiline":
        sys.stdout.write({version!r} + "\nextra\n")
        raise SystemExit(0)
    elif MODE == "version-empty":
        raise SystemExit(0)
    elif MODE == "version-stderr":
        sys.stderr.write("version warning\n")
        sys.stdout.write({version!r} + "\n")
        raise SystemExit(0)
    elif MODE == "version-nonutf8":
        sys.stdout.buffer.write(b"jq-\xff\n")
        raise SystemExit(0)
    elif MODE == "version-detached-child":
        child = os.fork()
        if child == 0:
            os.setsid()
            pathlib.Path(TARGET).write_text(str(os.getpid()), encoding="ascii")
            devnull = os.open("/dev/null", os.O_RDWR)
            for descriptor in (0, 1, 2):
                os.dup2(devnull, descriptor)
            time.sleep(60)
            os._exit(0)
        deadline = time.monotonic() + 1
        while not pathlib.Path(TARGET).exists() and time.monotonic() < deadline:
            time.sleep(0.002)
    elif MODE == "version-mutate-exec-mode":
        mutated = False
        for name in os.listdir("/proc/self/fd"):
            try:
                target = os.readlink("/proc/self/fd/" + name)
                if "memfd:shtest-candidate" in target:
                    os.fchmod(int(name), 0)
                    mutated = True
            except OSError:
                pass
        pathlib.Path(TARGET).write_text(
            "metadata-mutated" if mutated else "metadata-protected",
            encoding="ascii",
        )
    elif MODE == "replace-interpreter":
        replacement = pathlib.Path(TARGET + ".replacement")
        shutil.copyfile("/bin/false", replacement)
        replacement.chmod(0o755)
        os.replace(replacement, TARGET)
    sys.stdout.write({version!r} + "\n")
    raise SystemExit(0)

if MODE.startswith("version-") and MODE != "version-mutate-exec-mode" and TARGET:
    pathlib.Path(TARGET).write_text("candidate case executed", encoding="utf-8")

if MODE == "hang-candidate":
    marker = pathlib.Path(TARGET)
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    marker.write_text(f"{{child.pid}} {{os.getpgid(child.pid)}}", encoding="ascii")
    sys.stdout.buffer.write(b"before-timeout-out\xff")
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(b"before-timeout-err\xfe")
    sys.stderr.buffer.flush()
    time.sleep(60)

if MODE == "escape-candidate":
    marker = pathlib.Path(TARGET)
    child = subprocess.Popen(
        [
            sys.executable,
            "-c",
            "import pathlib,time; "
            "pathlib.Path('escaped-file').write_bytes(b'hostile'); "
            "time.sleep(60)",
        ],
        start_new_session=True,
    )
    marker.write_text(f"{{child.pid}} {{os.getpgid(child.pid)}}", encoding="ascii")
    sys.stdout.buffer.write(b"leader-exited")
    sys.stdout.buffer.flush()
    raise SystemExit(0)

if MODE == "detached-matching-candidate":
    child = os.fork()
    if child == 0:
        os.setsid()
        pathlib.Path(TARGET).write_text(str(os.getpid()), encoding="ascii")
        devnull = os.open("/dev/null", os.O_RDWR)
        for descriptor in (0, 1, 2):
            os.dup2(devnull, descriptor)
        time.sleep(60)
        os._exit(0)
    deadline = time.monotonic() + 1
    while not pathlib.Path(TARGET).exists() and time.monotonic() < deadline:
        time.sleep(0.002)

if MODE == "escape-storm":
    marker = pathlib.Path(TARGET)
    storm_code = r"""import os,pathlib,subprocess,sys,time
marker = pathlib.Path(sys.argv[1])
def start_time(pid):
    value = pathlib.Path(f"/proc/{{pid}}/stat").read_text(encoding="ascii")
    return value[value.rindex(")") + 2:].split()[19]
with marker.open("a", encoding="ascii", buffering=1) as output:
    output.write(f"{{os.getpid()}} {{start_time(os.getpid())}}\n")
    for _ in range(80):
        child = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            start_new_session=True,
        )
        output.write(f"{{child.pid}} {{start_time(child.pid)}}\n")
        time.sleep(0.002)
    time.sleep(60)
"""
    subprocess.Popen(
        [sys.executable, "-c", storm_code, str(marker)],
        start_new_session=True,
    )
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        if marker.exists() and len(marker.read_text(encoding="ascii").splitlines()) >= 8:
            break
        time.sleep(0.002)
    sys.stdout.buffer.write(b"storm-started")
    sys.stdout.buffer.flush()
    raise SystemExit(0)

if MODE == "stdout-flood":
    while True:
        os.write(1, b"x" * 65536)

if MODE == "stderr-flood":
    while True:
        os.write(2, b"y" * 65536)

operation = sys.argv[1]
data = sys.stdin.buffer.read()
if operation == "success":
    stdout, stderr, status = b"out\x00\xff", b"err\xfe", 0
elif operation == "binary":
    stdout, stderr, status = b"\x00\xff" + data, b"\xfeerr\x00", 0
elif operation == "exit":
    stdout, stderr, status = b"partial-out", b"partial-err", 7
elif operation == "inspect":
    parent = pathlib.Path(sys.argv[2])
    clean = "SHTEST_TEST_SECRET" not in os.environ
    isolated = pathlib.Path.cwd() != parent and os.environ.get("HOME") == str(pathlib.Path.cwd()) and os.environ.get("TMPDIR") == str(pathlib.Path.cwd())
    pathlib.Path("created-by-child").write_bytes(b"temporary")
    stdout, stderr, status = (b"isolated" if clean and isolated else b"leaked"), b"", 0
elif operation == "at-cap":
    stdout, stderr, status = b"x" * 1048576, b"y" * 1048576, 0
elif operation == "hang":
    marker = pathlib.Path(sys.argv[2])
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    marker.write_text(str(child.pid), encoding="ascii")
    sys.stdout.buffer.write(b"before-timeout-out\xff")
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(b"before-timeout-err\xfe")
    sys.stderr.buffer.flush()
    time.sleep(60)
elif operation == "self-signal":
    os.kill(os.getpid(), signal.SIGTERM)
else:
    stdout, stderr, status = b"", b"unknown operation", 99

if MODE == "stdout-mismatch":
    stdout += b"different"
elif MODE == "stderr-mismatch":
    stderr += b"different"
elif MODE == "exit-mismatch":
    status = 9
elif MODE == "signal" and operation != "inspect":
    os.kill(os.getpid(), signal.SIGTERM)
elif MODE == "clobber":
    stdout = b"candidate-after-clobber"

sys.stdout.buffer.write(stdout)
sys.stderr.buffer.write(stderr)
raise SystemExit(status)
'''


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def run_case(
    case_id: str = "case-one",
    argv: list[str] | None = None,
    stdin: bytes = b"input",
    timeout: float = 2,
) -> dict[str, object]:
    return {
        "id": case_id,
        "kind": "run",
        "provenance": {
            "source": "upstream/jq/tests/shtest",
            "line_start": 38,
            "line_end": 40,
        },
        "argv": argv or ["success"],
        "stdin_b64": b64(stdin),
        "timeout_seconds": timeout,
    }


def skip_case(case_id: str = "unsupported") -> dict[str, object]:
    return {
        "id": case_id,
        "kind": "skip",
        "provenance": {
            "source": "upstream/jq/tests/shtest",
            "line_start": 145,
            "line_end": 149,
        },
        "reason": "requires a two-process pipeline",
    }


class CatalogTests(unittest.TestCase):
    def load_value(self, value: object) -> list[object]:
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "catalog.json"
            path.write_text(json.dumps(value), encoding="utf-8")
            return SHTEST.load_catalog(path)

    def assert_catalog_error(self, value: object, message: str) -> None:
        with self.assertRaisesRegex(SHTEST.HarnessError, message):
            self.load_value(value)

    def test_loads_binary_stdin_and_skip(self) -> None:
        cases = self.load_value(
            {"schema_version": 1, "cases": [run_case(stdin=b"\x00\xff"), skip_case()]}
        )
        self.assertEqual(cases[0].stdin, b"\x00\xff")
        self.assertEqual(cases[1].kind, "skip")
        self.assertTrue(cases[1].skip_reason)

    def test_rejects_malformed_catalog_and_entries(self) -> None:
        valid = run_case()
        malformed: list[tuple[object, str]] = [
            ({"schema_version": 1, "cases": [valid], "extra": 1}, "unknown fields"),
            ({"schema_version": True, "cases": [valid]}, "schema_version"),
            ({"schema_version": 1, "cases": []}, "non-empty array"),
            ({"schema_version": 1, "cases": [valid, valid]}, "duplicate case ID"),
            ({"schema_version": 1, "cases": [{**valid, "id": "Bad ID"}]}, "invalid case ID"),
            ({"schema_version": 1, "cases": [{**valid, "argv": "not-array"}]}, "non-empty array"),
            ({"schema_version": 1, "cases": [{**valid, "argv": [1]}]}, "every element"),
            ({"schema_version": 1, "cases": [{**valid, "argv": ["a\x00b"]}]}, "NUL"),
            ({"schema_version": 1, "cases": [{**valid, "stdin_b64": "***"}]}, "invalid Base64"),
            ({"schema_version": 1, "cases": [{**valid, "stdin_b64": "YQ"}]}, "invalid Base64"),
            ({"schema_version": 1, "cases": [{**valid, "timeout_seconds": True}]}, "finite number"),
            ({"schema_version": 1, "cases": [{**valid, "timeout_seconds": 0}]}, "greater than zero"),
            ({"schema_version": 1, "cases": [{**skip_case(), "reason": ""}]}, "non-empty string"),
            ({"schema_version": 1, "cases": [{**valid, "surprise": 1}]}, "unknown fields"),
        ]
        for value, message in malformed:
            with self.subTest(message=message):
                self.assert_catalog_error(value, message)

    def test_rejects_duplicate_json_object_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "catalog.json"
            path.write_text('{"schema_version":1,"schema_version":1,"cases":[]}', encoding="utf-8")
            with self.assertRaisesRegex(SHTEST.HarnessError, "duplicate object key"):
                SHTEST.load_catalog(path)

    def test_timeout_numeric_bounds_are_validated_consistently(self) -> None:
        for timeout in (0.125, SHTEST.MAX_TIMEOUT_SECONDS):
            with self.subTest(timeout=timeout):
                cases = self.load_value(
                    {"schema_version": 1, "cases": [run_case(timeout=timeout)]}
                )
                self.assertEqual(cases[0].timeout_seconds, float(timeout))

        for timeout in (
            float("-inf"),
            -10**400,
            -1,
            SHTEST.MAX_TIMEOUT_SECONDS + 0.001,
            10**400,
            float("inf"),
            float("nan"),
        ):
            with self.subTest(timeout=timeout):
                self.assert_catalog_error(
                    {"schema_version": 1, "cases": [run_case(timeout=timeout)]},
                    "greater than zero and at most 60",
                )


class PathStagingTests(unittest.TestCase):
    def material(self, path: str, marker: int = 1) -> object:
        return SHTEST.PathMaterial(
            pathlib.Path(path),
            marker,
            f"{marker:064x}",
            False,
            marker + 100,
            marker + 200,
        )

    def launch(
        self,
        anchor: str,
        staging: str,
        *materials: object,
        directory_fd: int = 10,
    ) -> object:
        return SHTEST.PathLaunch(
            pathlib.Path(anchor),
            directory_fd,
            tuple(materials),
            pathlib.Path(staging),
        )

    def test_launch_normalization_is_ancestor_first_and_order_independent(self) -> None:
        ancestor = self.launch(
            "/tree", "/stage/z", self.material("/tree/ancestor", 1)
        )
        descendant = self.launch(
            "/tree/child", "/stage/y", self.material("/tree/child/leaf", 2)
        )
        unrelated = self.launch(
            "/other", "/stage/x", self.material("/other/value", 3)
        )
        expected = SHTEST.normalize_path_launches(
            (descendant, unrelated, ancestor)
        )
        self.assertEqual(
            SHTEST.normalize_path_launches((ancestor, descendant, unrelated)),
            expected,
        )
        self.assertEqual(
            [launch.anchor for launch in expected],
            [pathlib.Path("/other"), pathlib.Path("/tree"), pathlib.Path("/tree/child")],
        )

    def test_launch_normalization_deduplicates_equal_launches_stably(self) -> None:
        first = self.launch(
            "/tree", "/stage/z", self.material("/tree/b", 2)
        )
        second = self.launch(
            "/tree", "/stage/a", self.material("/tree/a", 1)
        )
        normalized = SHTEST.normalize_path_launches((first, second, first))
        self.assertEqual(len(normalized), 1)
        self.assertEqual(normalized[0].staging_path, pathlib.Path("/stage/a"))
        self.assertEqual(
            [material.path for material in normalized[0].materials],
            [pathlib.Path("/tree/a"), pathlib.Path("/tree/b")],
        )

    def test_real_overlapping_mounts_preserve_both_sealed_targets(self) -> None:
        if not hasattr(os, "memfd_create") or not hasattr(os, "unshare"):
            self.skipTest("Linux memfd or namespaces are unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            anchor = pathlib.Path(temporary) / "anchor"
            child = anchor / "child"
            child.mkdir(parents=True)
            ancestor_target = anchor / "ancestor"
            descendant_target = child / "descendant"
            ancestor_target.write_bytes(b"HOST-ANCESTOR")
            descendant_target.write_bytes(b"HOST-DESCENDANT")
            descriptors: list[int] = []
            staging_paths: list[pathlib.Path] = []
            try:
                materials = []
                for name, path, payload in (
                    ("ancestor", ancestor_target, b"SEALED-ANCESTOR"),
                    ("descendant", descendant_target, b"SEALED-DESCENDANT"),
                ):
                    flags = os.MFD_CLOEXEC | getattr(os, "MFD_ALLOW_SEALING", 0x0002)
                    descriptor = os.memfd_create(f"shtest-overlap-{name}", flags)
                    descriptors.append(descriptor)
                    os.write(descriptor, payload)
                    seals = (
                        SHTEST.fcntl.F_SEAL_SEAL
                        | SHTEST.fcntl.F_SEAL_SHRINK
                        | SHTEST.fcntl.F_SEAL_GROW
                        | SHTEST.fcntl.F_SEAL_WRITE
                    )
                    SHTEST.fcntl.fcntl(descriptor, SHTEST.fcntl.F_ADD_SEALS, seals)
                    materials.append(
                        SHTEST.PathMaterial(
                            path,
                            descriptor,
                            hashlib.sha256(payload).hexdigest(),
                            False,
                            -1,
                            -1,
                        )
                    )
                for reverse in (False, True):
                    with self.subTest(reverse=reverse):
                        ancestor_fd = os.open(
                            anchor, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC
                        )
                        descendant_fd = os.open(
                            child, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC
                        )
                        descriptors.extend((ancestor_fd, descendant_fd))
                        ancestor_staging = SHTEST.create_path_staging({anchor, child})
                        descendant_staging = SHTEST.create_path_staging({anchor, child})
                        staging_paths.extend((ancestor_staging, descendant_staging))
                        launches = (
                            SHTEST.PathLaunch(
                                anchor,
                                ancestor_fd,
                                (materials[0],),
                                ancestor_staging,
                            ),
                            SHTEST.PathLaunch(
                                child,
                                descendant_fd,
                                (materials[1],),
                                descendant_staging,
                            ),
                        )
                        if reverse:
                            launches = tuple(reversed(launches))
                        read_fd, write_fd = os.pipe()
                        child_pid = os.fork()
                        if child_pid == 0:
                            os.close(read_fd)
                            try:
                                SHTEST.prepare_path_launches(launches)
                                observed = (
                                    ancestor_target.read_bytes()
                                    + b"\0"
                                    + descendant_target.read_bytes()
                                )
                                os.write(write_fd, b"OK\0" + observed)
                            except OSError as exc:
                                os.write(
                                    write_fd,
                                    f"OSERROR\0{exc.errno}\0{exc}".encode("utf-8"),
                                )
                            except BaseException as exc:
                                os.write(write_fd, f"ERROR\0{exc}".encode("utf-8"))
                            finally:
                                os._exit(0)
                        os.close(write_fd)
                        observed = b""
                        while True:
                            chunk = os.read(read_fd, 4096)
                            if not chunk:
                                break
                            observed += chunk
                        os.close(read_fd)
                        _, status = os.waitpid(child_pid, 0)
                        self.assertTrue(os.WIFEXITED(status))
                        if observed.startswith(b"OSERROR\0"):
                            error_number = int(observed.split(b"\0", 2)[1])
                            if error_number in (1, 13, 38, 95):
                                self.skipTest(
                                    "unprivileged user/mount namespaces or overlayfs "
                                    "are unavailable"
                                )
                        self.assertEqual(
                            observed,
                            b"OK\0SEALED-ANCESTOR\0SEALED-DESCENDANT",
                        )
            finally:
                for descriptor in descriptors:
                    os.close(descriptor)
                for staging_path in staging_paths:
                    shutil.rmtree(staging_path, ignore_errors=True)

    def test_dev_anchor_rejects_dev_shm_and_selects_safe_base(self) -> None:
        with (
            mock.patch.object(pathlib.Path, "is_dir", return_value=True),
            mock.patch.object(
                SHTEST.tempfile,
                "mkdtemp",
                return_value="/tmp/.shtest-path-launch-safe",
            ) as mkdtemp,
        ):
            staging = SHTEST.create_path_staging({pathlib.Path("/dev")})

        self.assertEqual(staging, pathlib.Path("/tmp/.shtest-path-launch-safe"))
        mkdtemp.assert_called_once_with(
            prefix=".shtest-path-launch-", dir=pathlib.Path("/tmp")
        )

    def test_tmp_and_workspace_anchors_choose_only_outside_all_anchors(self) -> None:
        anchors = {pathlib.Path("/tmp"), pathlib.Path("/workspace")}
        attempted_bases: list[pathlib.Path] = []

        def create(*, prefix: str, dir: pathlib.Path) -> str:
            self.assertEqual(prefix, ".shtest-path-launch-")
            attempted_bases.append(dir)
            if dir == pathlib.Path("/dev/shm"):
                raise OSError("candidate unavailable")
            return str(dir / f"{prefix}safe")

        with (
            mock.patch.object(pathlib.Path, "is_dir", return_value=True),
            mock.patch.object(SHTEST.tempfile, "mkdtemp", side_effect=create),
        ):
            staging = SHTEST.create_path_staging(anchors)

        self.assertEqual(
            attempted_bases, [pathlib.Path("/dev/shm"), pathlib.Path("/run")]
        )
        self.assertEqual(staging.parent, pathlib.Path("/run"))
        self.assertTrue(
            all(not staging.parent.is_relative_to(anchor) for anchor in anchors)
        )

    def test_multiple_anchors_are_considered_together(self) -> None:
        anchors = {
            pathlib.Path("/dev"),
            pathlib.Path("/tmp"),
            pathlib.Path("/workspace"),
        }
        with (
            mock.patch.object(pathlib.Path, "is_dir", return_value=True),
            mock.patch.object(
                SHTEST.tempfile,
                "mkdtemp",
                return_value="/run/.shtest-path-launch-safe",
            ) as mkdtemp,
        ):
            staging = SHTEST.create_path_staging(anchors)

        self.assertEqual(staging.parent, pathlib.Path("/run"))
        mkdtemp.assert_called_once_with(
            prefix=".shtest-path-launch-", dir=pathlib.Path("/run")
        )
        self.assertTrue(
            all(not staging.parent.is_relative_to(anchor) for anchor in anchors)
        )

    def test_exhausted_bases_fail_closed_without_unsafe_mkdtemp(self) -> None:
        anchors = {
            pathlib.Path("/dev"),
            pathlib.Path("/tmp"),
            pathlib.Path("/run"),
        }
        with (
            mock.patch.object(pathlib.Path, "is_dir", return_value=True),
            mock.patch.object(SHTEST.tempfile, "mkdtemp") as mkdtemp,
            self.assertRaisesRegex(
                OSError,
                "cannot create private path staging outside namespace anchors",
            ),
        ):
            SHTEST.create_path_staging(anchors)

        mkdtemp.assert_not_called()


class RunnerTests(unittest.TestCase):
    def build_native_cli(
        self,
        directory: pathlib.Path,
        name: str,
        *,
        dynamic_linker: pathlib.Path | None = None,
    ) -> pathlib.Path:
        source = directory / f"{name}.c"
        executable = directory / name
        source.write_text(
            "#include <stdio.h>\n"
            "#include <string.h>\n"
            "int main(int argc, char **argv) {\n"
            '  if (argc > 1 && strcmp(argv[1], "--version") == 0) {\n'
            '    puts("jq-1.8.1");\n'
            "    return 0;\n"
            "  }\n"
            '  fwrite("out\\0\\xff", 1, 5, stdout);\n'
            '  fwrite("err\\xfe", 1, 4, stderr);\n'
            "  return 0;\n"
            "}\n",
            encoding="ascii",
        )
        command = ["cc", str(source), "-o", str(executable)]
        if dynamic_linker is not None:
            command.append(f"-Wl,--dynamic-linker={dynamic_linker}")
        subprocess.run(
            command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        return executable

    def build_origin_elf(
        self,
        directory: pathlib.Path,
        name: str,
        message: str,
        *,
        interpreter: bool = False,
    ) -> tuple[pathlib.Path, pathlib.Path]:
        library_source = directory / f"{name}-library.c"
        program_source = directory / f"{name}.c"
        library = directory / f"lib{name}.so"
        program = directory / name
        library_source.write_text(
            f'const char *fixture_message(void) {{ return "{message}"; }}\n',
            encoding="ascii",
        )
        argument_index = 2 if interpreter else 1
        program_source.write_text(
            "#include <stdio.h>\n"
            "#include <string.h>\n"
            "extern const char *fixture_message(void);\n"
            "int main(int argc, char **argv) {\n"
            f"  if (argc > {argument_index} && "
            f"strcmp(argv[{argument_index}], \"--version\") == 0) {{\n"
            '    puts("jq-1.8.1");\n'
            "    return 0;\n"
            "  }\n"
            "  puts(fixture_message());\n"
            "  return 0;\n"
            "}\n",
            encoding="ascii",
        )
        subprocess.run(
            ["cc", "-shared", "-fPIC", str(library_source), "-o", str(library)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            [
                "cc",
                str(program_source),
                "-L",
                str(directory),
                f"-l{name}",
                "-Wl,-rpath,$ORIGIN",
                "-o",
                str(program),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return program, library

    def replace_origin_library(
        self, directory: pathlib.Path, name: str, message: str
    ) -> None:
        source = directory / f"{name}-replacement.c"
        replacement = directory / f"lib{name}.replacement.so"
        source.write_text(
            f'const char *fixture_message(void) {{ return "{message}"; }}\n',
            encoding="ascii",
        )
        subprocess.run(
            ["cc", "-shared", "-fPIC", str(source), "-o", str(replacement)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        os.replace(replacement, directory / f"lib{name}.so")

    def build_recursive_origin_elf(
        self,
        hierarchy: pathlib.Path,
        name: str,
        message: str,
        *,
        interpreter: bool = False,
    ) -> tuple[pathlib.Path, tuple[pathlib.Path, pathlib.Path]]:
        """Build bin/image -> ../lib/libmiddle -> lib leaf fixtures."""
        binary_directory = hierarchy / "bin"
        library_directory = hierarchy / "lib"
        binary_directory.mkdir(parents=True)
        library_directory.mkdir(parents=True)
        leaf_source = hierarchy / f"{name}-leaf.c"
        middle_source = hierarchy / f"{name}-middle.c"
        program_source = hierarchy / f"{name}.c"
        leaf = library_directory / f"lib{name}_leaf.so"
        middle = library_directory / f"lib{name}_middle.so"
        program = binary_directory / name
        leaf_source.write_text(
            f'const char *leaf_message(void) {{ return "{message}"; }}\n',
            encoding="ascii",
        )
        middle_source.write_text(
            "extern const char *leaf_message(void);\n"
            "const char *fixture_message(void) { return leaf_message(); }\n",
            encoding="ascii",
        )
        argument_index = 2 if interpreter else 1
        program_source.write_text(
            "#include <stdio.h>\n#include <string.h>\n"
            "extern const char *fixture_message(void);\n"
            "int main(int argc, char **argv) {\n"
            f"  if (argc > {argument_index} && "
            f"strcmp(argv[{argument_index}], \"--version\") == 0) {{\n"
            '    puts("jq-1.8.1"); return 0;\n'
            "  }\n"
            "  puts(fixture_message()); return 0;\n}\n",
            encoding="ascii",
        )
        subprocess.run(
            ["cc", "-shared", "-fPIC", str(leaf_source), "-o", str(leaf)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            [
                "cc", "-shared", "-fPIC", str(middle_source),
                "-L", str(library_directory), f"-l{name}_leaf",
                "-Wl,-rpath,$ORIGIN", "-o", str(middle),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            [
                "cc", str(program_source), "-L", str(library_directory),
                f"-l{name}_middle", "-Wl,-rpath,$ORIGIN/../lib",
                "-o", str(program),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return program, (middle, leaf)

    def build_transitive_search_elf(
        self,
        hierarchy: pathlib.Path,
        name: str,
        message: str,
        *,
        legacy_rpath: bool,
        interpreter: bool = False,
        library_subdirectory: str = "lib",
        rpath: str = "$ORIGIN/../lib",
    ) -> tuple[pathlib.Path, tuple[pathlib.Path, pathlib.Path]]:
        """Build an untagged middle resolved only by the executable's search tag."""
        binary_directory = hierarchy / "bin"
        library_directory = hierarchy / library_subdirectory
        binary_directory.mkdir(parents=True)
        library_directory.mkdir(parents=True)
        leaf_source = hierarchy / f"{name}-leaf.c"
        middle_source = hierarchy / f"{name}-middle.c"
        program_source = hierarchy / f"{name}.c"
        leaf = library_directory / f"lib{name}_leaf.so"
        middle = library_directory / f"lib{name}_middle.so"
        program = binary_directory / name
        leaf_source.write_text(
            f'const char *leaf_message(void) {{ return "{message}"; }}\n',
            encoding="ascii",
        )
        middle_source.write_text(
            "extern const char *leaf_message(void);\n"
            "const char *fixture_message(void) { return leaf_message(); }\n",
            encoding="ascii",
        )
        argument_index = 2 if interpreter else 1
        program_source.write_text(
            "#include <stdio.h>\n#include <string.h>\n"
            "extern const char *fixture_message(void);\n"
            "int main(int argc, char **argv) {\n"
            f"  if (argc > {argument_index} && "
            f"strcmp(argv[{argument_index}], \"--version\") == 0) {{\n"
            '    puts("jq-1.8.1"); return 0;\n'
            "  }\n"
            "  puts(fixture_message()); return 0;\n}\n",
            encoding="ascii",
        )
        subprocess.run(
            [
                "cc", "-shared", "-fPIC", str(leaf_source),
                f"-Wl,-soname,{leaf.name}", "-o", str(leaf),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            [
                "cc", "-shared", "-fPIC", str(middle_source),
                "-L", str(library_directory), f"-l{name}_leaf",
                f"-Wl,-soname,{middle.name}", "-o", str(middle),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        dtag = "--disable-new-dtags" if legacy_rpath else "--enable-new-dtags"
        subprocess.run(
            [
                "cc", str(program_source), "-L", str(library_directory),
                f"-l{name}_middle", f"-Wl,-rpath-link,{library_directory}",
                f"-Wl,{dtag},-rpath,{rpath}", "-o", str(program),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return program, (middle, leaf)

    def dynamic_tags(self, path: pathlib.Path) -> str:
        return subprocess.run(
            ["readelf", "-d", str(path)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ).stdout

    def replace_elf_dynamic_tag(
        self, path: pathlib.Path, old_tag: int, new_tag: int
    ) -> None:
        image = bytearray(path.read_bytes())
        elf_class, data_encoding = image[4], image[5]
        endian = "<" if data_encoding == 1 else ">"
        header_format = endian + (
            "16sHHIIIIIHHHHHH" if elf_class == 1 else "16sHHIQQQIHHHHHH"
        )
        header = struct.unpack_from(header_format, image)
        phoff, phentsize, phnum = header[5], header[9], header[10]
        program_format = endian + ("IIIIIIII" if elf_class == 1 else "IIQQQQQQ")
        dynamic_format = endian + ("iI" if elf_class == 1 else "qQ")
        dynamic_size = struct.calcsize(dynamic_format)
        for index in range(phnum):
            fields = struct.unpack_from(
                program_format, image, phoff + index * phentsize
            )
            if fields[0] != 2:
                continue
            dynamic_offset = fields[1] if elf_class == 1 else fields[2]
            dynamic_length = fields[4] if elf_class == 1 else fields[5]
            for offset in range(
                dynamic_offset, dynamic_offset + dynamic_length, dynamic_size
            ):
                tag, value = struct.unpack_from(dynamic_format, image, offset)
                if tag == old_tag:
                    struct.pack_into(dynamic_format, image, offset, new_tag, value)
                    path.write_bytes(image)
                    return
        self.fail(f"ELF dynamic tag {old_tag} was not found in {path}")

    def test_missing_dynamic_string_table_is_structured_schema_v5(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            report_path = directory / "report.json"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            oracle = self.build_native_cli(directory, "oracle")
            candidate = self.build_native_cli(directory, "candidate")
            self.replace_elf_dynamic_tag(candidate, 5, 0x6FFFF000)

            completed = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER),
                    "--catalog",
                    str(catalog),
                    "--oracle",
                    str(oracle),
                    "--candidate",
                    str(candidate),
                    "--json-report",
                    str(report_path),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            self.assertEqual(completed.returncode, 2)
            self.assertNotIn("Traceback", completed.stdout + completed.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["schema_version"], 5)
            self.assertEqual(report["startup_failure"]["stage"], "version_probe")
            self.assertEqual(report["startup_failure"]["role"], "candidate")
            self.assertEqual(report["candidate"]["path"], str(candidate))
            self.assertIsNotNone(report["candidate"]["sha256"])
            self.assertEqual(len(report["candidate"]["dependencies"]), 1)

    def build_dynamic_token_elf(
        self,
        hierarchy: pathlib.Path,
        name: str,
        message: str,
        rpath: str,
        expanded_directory: pathlib.Path,
        *,
        legacy_rpath: bool = False,
    ) -> tuple[pathlib.Path, pathlib.Path]:
        binary_directory = hierarchy / "bin"
        binary_directory.mkdir(parents=True)
        expanded_directory.mkdir(parents=True, exist_ok=True)
        library_source = hierarchy / f"{name}-library.c"
        program_source = hierarchy / f"{name}.c"
        library = expanded_directory / f"lib{name}.so"
        program = binary_directory / name
        library_source.write_text(
            f'const char *fixture_message(void) {{ return "{message}"; }}\n',
            encoding="ascii",
        )
        program_source.write_text(
            "#include <stdio.h>\n#include <string.h>\n"
            "extern const char *fixture_message(void);\n"
            "int main(int argc, char **argv) {\n"
            "  if (argc > 1 && strcmp(argv[1], \"--version\") == 0) {\n"
            '    puts("jq-1.8.1"); return 0;\n'
            "  }\n"
            "  puts(fixture_message()); return 0;\n}\n",
            encoding="ascii",
        )
        subprocess.run(
            [
                "cc", "-shared", "-fPIC", str(library_source),
                f"-Wl,-soname,{library.name}", "-o", str(library),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        dtag = "--disable-new-dtags" if legacy_rpath else "--enable-new-dtags"
        subprocess.run(
            [
                "cc", str(program_source), "-L", str(expanded_directory),
                f"-l{name}", f"-Wl,{dtag},-rpath,{rpath}", "-o", str(program),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return program, library

    def compile_message_library(
        self,
        path: pathlib.Path,
        message: str,
        *,
        soname: str | None = None,
        symbol: str = "fixture_message",
    ) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        source = path.with_suffix(path.suffix + ".c")
        source.write_text(
            f'const char *{symbol}(void) {{ return "{message}"; }}\n',
            encoding="ascii",
        )
        command = ["cc", "-shared", "-fPIC", str(source)]
        if soname is not None:
            command.append(f"-Wl,-soname,{soname}")
        command.extend(["-o", str(path)])
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def build_hwcaps_elf(
        self,
        hierarchy: pathlib.Path,
        name: str,
        levels: tuple[str, ...],
        *,
        interpreter: bool = False,
    ) -> tuple[pathlib.Path, pathlib.Path, tuple[pathlib.Path, ...]]:
        binary_directory = hierarchy / "bin"
        library_directory = hierarchy / "lib"
        binary_directory.mkdir(parents=True)
        base = library_directory / f"lib{name}.so"
        self.compile_message_library(base, "sealed-base", soname=base.name)
        variants: list[pathlib.Path] = []
        for index, level in enumerate(levels):
            level_directory = library_directory / "glibc-hwcaps" / level
            leaf = level_directory / f"lib{name}_leaf.so"
            variant = level_directory / base.name
            self.compile_message_library(
                leaf,
                f"sealed-{level}",
                soname=leaf.name,
                symbol="leaf_message",
            )
            source = variant.with_suffix(".c")
            source.write_text(
                "extern const char *leaf_message(void);\n"
                "const char *fixture_message(void) { return leaf_message(); }\n",
                encoding="ascii",
            )
            subprocess.run(
                [
                    "cc", "-shared", "-fPIC", str(source),
                    "-L", str(level_directory), f"-l{name}_leaf",
                    "-Wl,-rpath,$ORIGIN", f"-Wl,-soname,{base.name}",
                    "-o", str(variant),
                ],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            variants.extend((variant, leaf))
        program_source = hierarchy / f"{name}.c"
        argument_index = 2 if interpreter else 1
        program_source.write_text(
            "#include <stdio.h>\n#include <string.h>\n"
            "extern const char *fixture_message(void);\n"
            "int main(int argc, char **argv) {\n"
            f"  if (argc > {argument_index} && strcmp(argv[{argument_index}], \"--version\") == 0) {{\n"
            '    puts("jq-1.8.1"); return 0;\n'
            "  }\n"
            "  puts(fixture_message()); return 0;\n}\n",
            encoding="ascii",
        )
        program = binary_directory / name
        subprocess.run(
            [
                "cc", str(program_source), "-L", str(library_directory),
                f"-l{name}", "-Wl,-rpath,$ORIGIN/../lib", "-o", str(program),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return program, base, tuple(variants)

    def build_slash_needed_elf(
        self,
        hierarchy: pathlib.Path,
        name: str,
        spelling: str,
        *,
        transitive: bool = False,
    ) -> tuple[pathlib.Path, tuple[pathlib.Path, ...]]:
        binary_directory = hierarchy / "bin"
        library_directory = hierarchy / "lib"
        binary_directory.mkdir(parents=True)
        library_directory.mkdir(parents=True)
        leaf = library_directory / f"lib{name}_leaf.so"
        self.compile_message_library(
            leaf,
            "sealed-slash-needed",
            soname=(
                f"$ORIGIN/lib{name}_leaf.so"
                if transitive
                else f"{spelling}/lib{name}_leaf.so"
            ),
            symbol="leaf_message" if transitive else "fixture_message",
        )
        linked_library = leaf
        dependencies: tuple[pathlib.Path, ...] = (leaf,)
        if transitive:
            middle = library_directory / f"lib{name}_middle.so"
            middle_source = hierarchy / f"{name}-middle.c"
            middle_source.write_text(
                "extern const char *leaf_message(void);\n"
                "const char *fixture_message(void) { return leaf_message(); }\n",
                encoding="ascii",
            )
            subprocess.run(
                [
                    "cc", "-shared", "-fPIC", str(middle_source),
                    "-L", str(library_directory), f"-l{name}_leaf",
                    f"-Wl,-soname,{spelling}/lib{name}_middle.so",
                    "-o", str(middle),
                ],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            linked_library = middle
            dependencies = (middle, leaf)
        program_source = hierarchy / f"{name}.c"
        program_source.write_text(
            "#include <stdio.h>\n#include <string.h>\n"
            "extern const char *fixture_message(void);\n"
            "int main(int argc, char **argv) {\n"
            '  if (argc > 1 && strcmp(argv[1], "--version") == 0) {\n'
            '    puts("jq-1.8.1"); return 0;\n'
            "  }\n"
            "  puts(fixture_message()); return 0;\n}\n",
            encoding="ascii",
        )
        program = binary_directory / name
        subprocess.run(
            [
                "cc", str(program_source), str(linked_library),
                f"-Wl,-rpath-link,{library_directory}",
                "-Wl,--allow-shlib-undefined", "-o", str(program),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        return program, dependencies

    def runtime_tokens(self) -> SHTEST.DynamicLoaderTokens:
        loader = SHTEST.DynamicLoaderContext(SHTEST.active_dynamic_loader_path())
        budget = SHTEST.ExecutableCaptureBudget(time.monotonic() + 2)
        return SHTEST.dynamic_loader_tokens(
            loader, pathlib.Path(sys.executable), "test fixture", budget
        )

    def test_loader_hwcaps_priority_disagreement_fails_closed(self) -> None:
        active_loader = SHTEST.active_dynamic_loader_path()
        diagnostics = subprocess.CompletedProcess(
            [str(active_loader), "--list-diagnostics"],
            0,
            stdout=(
                b'dl_dst_lib="lib/x86_64-linux-gnu"\n'
                b'dl_platform="x86_64"\n'
                b'dl_hwcaps_subdirs="level-high:level-low"\n'
                b'dl_hwcaps_subdirs_active=0x1\n'
            ),
            stderr=b"",
        )
        help_output = subprocess.CompletedProcess(
            [str(active_loader), "--help"],
            0,
            stdout=(
                b"Subdirectories of glibc-hwcaps directories, in priority order:\n"
                b"  level-high\n"
                b"  level-low (supported, searched)\n"
            ),
            stderr=b"",
        )
        SHTEST._DYNAMIC_LOADER_TOKEN_CACHE.clear()
        try:
            with (
                mock.patch.object(
                    SHTEST, "active_dynamic_loader_path", return_value=active_loader
                ),
                mock.patch.object(
                    SHTEST.subprocess,
                    "run",
                    side_effect=(diagnostics, help_output),
                ),
                self.assertRaisesRegex(
                    SHTEST.HarnessError,
                    "inconsistent glibc-hwcaps priority",
                ),
            ):
                SHTEST.dynamic_loader_tokens(
                    SHTEST.DynamicLoaderContext(active_loader),
                    pathlib.Path(sys.executable),
                    "candidate",
                    SHTEST.ExecutableCaptureBudget(time.monotonic() + 2),
                )
        finally:
            SHTEST._DYNAMIC_LOADER_TOKEN_CACHE.clear()

    def assert_dynamic_token_dependency_is_sealed(
        self,
        hierarchy: pathlib.Path,
        name: str,
        rpath: str,
        expanded_directory: pathlib.Path,
    ) -> None:
        program, library = self.build_dynamic_token_elf(
            hierarchy, name, "captured-token-library", rpath, expanded_directory
        )
        tags = self.dynamic_tags(program)
        self.assertIn(rpath, tags)
        direct = subprocess.run(
            [str(program)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        self.assertEqual(direct.stdout, b"captured-token-library\n")
        image = SHTEST.capture_executable(program, "candidate")
        try:
            self.assertEqual(
                [dependency.path for dependency in image.origin_dependencies],
                [library],
            )
            report = SHTEST.executable_report(program, image, None, None)
            assert image.elf_interpreter is not None
            self.assertEqual(
                [entry["path"] for entry in report["dependencies"]],
                sorted((str(library), str(image.elf_interpreter.path))),
            )
            original_hash = hashlib.sha256(library.read_bytes()).hexdigest()
            self.replace_origin_library(
                expanded_directory, name, "live-token-replacement"
            )
            self.assertNotEqual(
                hashlib.sha256(library.read_bytes()).hexdigest(), original_hash
            )
            result = SHTEST.run_process(image, [], b"", 2, hierarchy)
            self.assertEqual(result.exit_status, 0)
            self.assertEqual(
                base64.b64decode(result.stdout_b64), b"captured-token-library\n"
            )
            self.assertFalse(result.cleanup_incomplete)
        finally:
            image.close()

    def replace_leaf_library(self, leaf: pathlib.Path, message: str) -> None:
        source = leaf.with_suffix(".replacement.c")
        replacement = leaf.with_suffix(".replacement.so")
        source.write_text(
            f'const char *leaf_message(void) {{ return "{message}"; }}\n',
            encoding="ascii",
        )
        subprocess.run(
            [
                "cc", "-shared", "-fPIC", str(source),
                f"-Wl,-soname,{leaf.name}", "-o", str(replacement),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        os.replace(replacement, leaf)

    def delayed_pipe_release(
        self,
        notify_read: int,
        notify_write: int,
        release_read: int,
        release_write: int,
        observed_read: int,
        observed_write: int,
        delay: float,
    ) -> int:
        """Fork a pipe-synchronized controller without sleeping in the proof path."""
        controller = os.fork()
        if controller == 0:
            try:
                os.close(notify_write)
                os.close(release_read)
                os.close(observed_read)
                observed = os.read(notify_read, 64)
                os.write(observed_write, observed)
                select.select([], [], [], delay)
                try:
                    os.write(release_write, b"release")
                except BrokenPipeError:
                    pass
            finally:
                os._exit(0)
        os.close(notify_read)
        os.close(release_write)
        os.close(observed_write)
        return controller

    def run_python_candidate(
        self, parent: pathlib.Path, code: str
    ) -> object:
        image = SHTEST.capture_executable(
            pathlib.Path(sys.executable).resolve(), "workspace-hostile-test"
        )
        try:
            return SHTEST.run_process(image, ["-c", code], b"", 2, parent)
        finally:
            image.close()

    def test_origin_runpath_native_roles_preserve_captured_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            program, library = self.build_origin_elf(
                directory, "nativefixture", "captured-native"
            )
            direct = subprocess.run(
                [str(program)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            self.assertEqual(direct.stdout, b"captured-native\n")

            oracle = SHTEST.capture_executable(program, "oracle")
            candidate = SHTEST.capture_executable(program, "candidate")
            baseline_fds = len(os.listdir("/proc/self/fd"))
            original_library_hash = hashlib.sha256(library.read_bytes()).hexdigest()
            try:
                self.assertEqual(
                    [item.sha256 for item in oracle.origin_dependencies],
                    [original_library_hash],
                )
                self.assertEqual(
                    [item.sha256 for item in candidate.origin_dependencies],
                    [original_library_hash],
                )
                self.replace_origin_library(
                    directory, "nativefixture", "host-replacement"
                )
                for role in (oracle, candidate):
                    with self.subTest(role=role.label):
                        version = SHTEST.run_process(role, ["--version"], b"", 2)
                        result = SHTEST.run_process(role, [], b"", 2)
                        self.assertEqual(version.exit_status, 0)
                        self.assertEqual(
                            base64.b64decode(version.stdout_b64), b"jq-1.8.1\n"
                        )
                        self.assertEqual(result.exit_status, 0)
                        self.assertEqual(
                            base64.b64decode(result.stdout_b64), b"captured-native\n"
                        )
                        self.assertFalse(result.cleanup_incomplete)
                        self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                library.unlink()
                missing_host = SHTEST.run_process(candidate, [], b"", 2)
                self.assertEqual(
                    base64.b64decode(missing_host.stdout_b64), b"captured-native\n"
                )
            finally:
                oracle.close()
                candidate.close()

    def test_active_glibc_hwcaps_priority_capture_schema_and_mutation_sealing(self) -> None:
        levels = self.runtime_tokens().hwcaps
        if not levels:
            self.skipTest("the active glibc loader reports no searched hwcaps level")
        with tempfile.TemporaryDirectory() as temporary:
            hierarchy = pathlib.Path(temporary) / "hwcaps-priority"
            program, base, variants = self.build_hwcaps_elf(
                hierarchy, "hwcapspriority", levels[:2]
            )
            selected = hierarchy / "lib" / "glibc-hwcaps" / levels[0] / base.name
            selected_leaf = selected.parent / "libhwcapspriority_leaf.so"
            direct = subprocess.run(
                [str(program)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            self.assertEqual(direct.stdout, f"sealed-{levels[0]}\n".encode("ascii"))
            self.assertGreaterEqual(len(variants), 2)
            image = SHTEST.capture_executable(program, "candidate")
            try:
                self.assertEqual(
                    {dependency.path for dependency in image.origin_dependencies},
                    {selected, selected_leaf},
                )
                report = SHTEST.executable_report(program, image, None, None)
                assert image.elf_interpreter is not None
                self.assertEqual(
                    [entry["path"] for entry in report["dependencies"]],
                    sorted(
                        (
                            str(selected),
                            str(selected_leaf),
                            str(image.elf_interpreter.path),
                        )
                    ),
                )
                expected_hashes = {
                    str(selected): hashlib.sha256(selected.read_bytes()).hexdigest(),
                    str(selected_leaf): hashlib.sha256(selected_leaf.read_bytes()).hexdigest(),
                    str(image.elf_interpreter.path): image.elf_interpreter.sha256,
                }
                self.assertEqual(
                    {entry["path"]: entry["sha256"] for entry in report["dependencies"]},
                    expected_hashes,
                )
                replacement = selected.with_suffix(".replacement.so")
                self.compile_message_library(
                    replacement, "live-selected-replacement", soname=base.name
                )
                os.replace(replacement, selected)
                result = SHTEST.run_process(image, [], b"", 2, hierarchy)
                self.assertEqual(result.exit_status, 0)
                self.assertEqual(
                    base64.b64decode(result.stdout_b64),
                    f"sealed-{levels[0]}\n".encode("ascii"),
                )
            finally:
                image.close()

    def test_glibc_hwcaps_base_fallback_masks_later_candidate_native_and_shebang(self) -> None:
        levels = self.runtime_tokens().hwcaps
        if not levels:
            self.skipTest("the active glibc loader reports no searched hwcaps level")
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            for interpreter in (False, True):
                with self.subTest(interpreter=interpreter):
                    hierarchy = root / ("shebang" if interpreter else "native")
                    program, base, _ = self.build_hwcaps_elf(
                        hierarchy,
                        "hwcapsfallback",
                        (),
                        interpreter=interpreter,
                    )
                    executable = program
                    if interpreter:
                        executable = hierarchy / "candidate-script"
                        executable.write_text(f"#!{program}\nignored\n", encoding="ascii")
                        executable.chmod(0o755)
                    direct = subprocess.run(
                        [str(executable)],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    self.assertEqual(direct.stdout, b"sealed-base\n")
                    image = SHTEST.capture_executable(executable, "candidate")
                    native_image = image.interpreter if interpreter else image
                    assert native_image is not None
                    try:
                        self.assertEqual(
                            [dependency.path for dependency in native_image.origin_dependencies],
                            [base],
                        )
                        higher = (
                            hierarchy / "lib" / "glibc-hwcaps" / levels[0] / base.name
                        )
                        self.compile_message_library(
                            higher, "live-later-hwcaps", soname=base.name
                        )
                        live = subprocess.run(
                            [str(executable)],
                            check=True,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                        )
                        self.assertEqual(live.stdout, b"live-later-hwcaps\n")
                        version = SHTEST.run_process(image, ["--version"], b"", 2, root)
                        result = SHTEST.run_process(image, [], b"", 2, root)
                        self.assertEqual(
                            base64.b64decode(version.stdout_b64), b"jq-1.8.1\n"
                        )
                        self.assertEqual(
                            base64.b64decode(result.stdout_b64), b"sealed-base\n"
                        )
                    finally:
                        image.close()

    def test_slash_needed_origin_bracing_absolute_and_transitive_are_sealed(self) -> None:
        tokens = self.runtime_tokens()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            fixtures = (
                ("unbraced", "$ORIGIN/../lib", False),
                ("braced", "${ORIGIN}/../lib", False),
                ("libtoken", "$ORIGIN/../$LIB/..", False),
                ("platformtoken", "${ORIGIN}/../lib/${PLATFORM}/..", False),
                ("absolute", str(root / "absolute" / "lib"), False),
                ("transitive", "$ORIGIN/../lib", True),
            )
            for name, spelling, transitive in fixtures:
                with self.subTest(name=name):
                    hierarchy = root / name
                    program, dependencies = self.build_slash_needed_elf(
                        hierarchy, f"slash{name}", spelling, transitive=transitive
                    )
                    if name == "libtoken":
                        (hierarchy / tokens.library).mkdir(parents=True, exist_ok=True)
                    elif name == "platformtoken":
                        (hierarchy / "lib" / tokens.platform).mkdir(
                            parents=True, exist_ok=True
                        )
                    program_tags = self.dynamic_tags(program)
                    self.assertIn("(NEEDED)", program_tags)
                    self.assertIn(
                        f"{spelling}/libslash{name}_{'middle' if transitive else 'leaf'}.so",
                        program_tags,
                    )
                    if transitive:
                        self.assertIn(
                            "$ORIGIN/libslashtransitive_leaf.so",
                            self.dynamic_tags(dependencies[0]),
                        )
                    direct = subprocess.run(
                        [str(program)],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    self.assertEqual(direct.stdout, b"sealed-slash-needed\n")
                    image = SHTEST.capture_executable(program, "candidate")
                    try:
                        self.assertEqual(
                            {dependency.path for dependency in image.origin_dependencies},
                            set(dependencies),
                        )
                        report = SHTEST.executable_report(program, image, None, None)
                        assert image.elf_interpreter is not None
                        self.assertEqual(
                            {entry["path"] for entry in report["dependencies"]},
                            {
                                *(str(path) for path in dependencies),
                                str(image.elf_interpreter.path),
                            },
                        )
                        self.compile_message_library(
                            dependencies[-1].with_suffix(".replacement.so"),
                            "live-slash-replacement",
                            soname=dependencies[-1].name,
                            symbol="leaf_message" if transitive else "fixture_message",
                        )
                        os.replace(
                            dependencies[-1].with_suffix(".replacement.so"),
                            dependencies[-1],
                        )
                        result = SHTEST.run_process(image, [], b"", 2, root)
                        self.assertEqual(result.exit_status, 0)
                        self.assertEqual(
                            base64.b64decode(result.stdout_b64),
                            b"sealed-slash-needed\n",
                        )
                    finally:
                        image.close()

    def test_slash_needed_relative_and_unresolved_forms_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            relative, _ = self.build_slash_needed_elf(
                root / "relative", "slashrelative", "../lib"
            )
            direct = subprocess.run(
                [str(relative)],
                cwd=relative.parent,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(direct.stdout, b"sealed-slash-needed\n")
            with self.assertRaisesRegex(
                SHTEST.HarnessError, "depends on the runtime working directory"
            ):
                SHTEST.capture_executable(relative, "candidate")

            unresolved, dependencies = self.build_slash_needed_elf(
                root / "unresolved", "slashunresolved", "$ORIGIN/../lib"
            )
            self.assertEqual(
                subprocess.run(
                    [str(unresolved)],
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                ).stdout,
                b"sealed-slash-needed\n",
            )
            dependencies[0].unlink()
            with self.assertRaisesRegex(
                SHTEST.HarnessError, "cannot resolve slash-bearing DT_NEEDED"
            ):
                SHTEST.capture_executable(unresolved, "candidate")

            unsupported, _ = self.build_slash_needed_elf(
                root / "unsupported", "slashunsupported", "$UNKNOWN/../lib"
            )
            with self.assertRaisesRegex(
                SHTEST.HarnessError, "unsupported ELF dynamic token"
            ):
                SHTEST.capture_executable(unsupported, "candidate")

    def test_origin_lib_spellings_capture_report_and_seal_loader_directory(self) -> None:
        tokens = self.runtime_tokens()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            for index, rpath in enumerate((
                "$ORIGIN/$LIB",
                "${ORIGIN}/${LIB}",
            )):
                with self.subTest(rpath=rpath):
                    hierarchy = root / f"lib-token-{index}"
                    self.assert_dynamic_token_dependency_is_sealed(
                        hierarchy,
                        f"libtoken{index}",
                        rpath,
                        hierarchy / "bin" / tokens.library,
                    )

    def test_origin_platform_bracing_and_boundary_capture_and_seal(self) -> None:
        tokens = self.runtime_tokens()
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            variants = (
                ("$ORIGIN/${PLATFORM}", tokens.platform),
                ("${ORIGIN}/$PLATFORM", tokens.platform),
                ("${ORIGIN}/${PLATFORM}-suffix", f"{tokens.platform}-suffix"),
            )
            for index, (rpath, directory_name) in enumerate(variants):
                with self.subTest(rpath=rpath):
                    hierarchy = root / f"platform-token-{index}"
                    self.assert_dynamic_token_dependency_is_sealed(
                        hierarchy,
                        f"platformtoken{index}",
                        rpath,
                        hierarchy / "bin" / directory_name,
                    )

    def test_origin_token_prefix_and_unknown_residual_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            for index, residual in enumerate(("$PLATFORM_SUFFIX", "$UNKNOWN")):
                with self.subTest(residual=residual):
                    hierarchy = root / f"residual-{index}"
                    program, _ = self.build_dynamic_token_elf(
                        hierarchy,
                        f"residual{index}",
                        "direct-still-works",
                        f"$ORIGIN:$ORIGIN/{residual}",
                        hierarchy / "bin",
                    )
                    direct = subprocess.run(
                        [str(program)],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    self.assertEqual(direct.stdout, b"direct-still-works\n")
                    with self.assertRaisesRegex(
                        SHTEST.HarnessError,
                        "unsupported ELF dynamic token",
                    ):
                        SHTEST.capture_executable(program, "candidate")

    def test_mixed_ordered_runpath_and_rpath_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            for legacy_rpath in (False, True):
                tag_name = "RPATH" if legacy_rpath else "RUNPATH"
                with self.subTest(tag=tag_name):
                    hierarchy = root / tag_name.lower()
                    origin_directory = hierarchy / "bin"
                    live_directory = hierarchy / "live"
                    name = f"mixed{tag_name.lower()}"
                    program, origin_library = self.build_dynamic_token_elf(
                        hierarchy,
                        name,
                        "later-origin",
                        f"{live_directory}:$ORIGIN",
                        origin_directory,
                        legacy_rpath=legacy_rpath,
                    )
                    live_library = live_directory / origin_library.name
                    self.compile_message_library(
                        live_library, "earlier-live", soname=origin_library.name
                    )
                    tags = self.dynamic_tags(program)
                    self.assertIn(f"({tag_name})", tags)
                    direct = subprocess.run(
                        [str(program)],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    self.assertEqual(direct.stdout, b"earlier-live\n")
                    origin_hash = hashlib.sha256(origin_library.read_bytes()).hexdigest()
                    live_hash = hashlib.sha256(live_library.read_bytes()).hexdigest()
                    self.assertNotEqual(live_hash, origin_hash)

                    self.compile_message_library(
                        live_library, "mutated-live", soname=origin_library.name
                    )
                    self.assertNotEqual(
                        hashlib.sha256(live_library.read_bytes()).hexdigest(), live_hash
                    )
                    self.assertEqual(
                        hashlib.sha256(origin_library.read_bytes()).hexdigest(),
                        origin_hash,
                    )
                    mutated = subprocess.run(
                        [str(program)],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    self.assertEqual(mutated.stdout, b"mutated-live\n")
                    with self.assertRaisesRegex(
                        SHTEST.HarnessError,
                        rf"{tag_name} search entry cannot be sealed without ORIGIN",
                    ):
                        SHTEST.capture_executable(program, "candidate")

    def test_origin_lib_composes_with_inherited_legacy_rpath(self) -> None:
        tokens = self.runtime_tokens()
        with tempfile.TemporaryDirectory() as temporary:
            hierarchy = pathlib.Path(temporary) / "legacy-lib-token"
            program, libraries = self.build_transitive_search_elf(
                hierarchy,
                "legacylibtoken",
                "captured-legacy-lib-token",
                legacy_rpath=True,
                library_subdirectory=tokens.library,
                rpath="$ORIGIN/../$LIB",
            )
            direct = subprocess.run(
                [str(program)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            self.assertEqual(direct.stdout, b"captured-legacy-lib-token\n")
            self.assertIn("(RPATH)", self.dynamic_tags(program))
            image = SHTEST.capture_executable(program, "candidate")
            middle, leaf = libraries
            try:
                self.assertEqual(
                    {dependency.path for dependency in image.origin_dependencies},
                    {middle, leaf},
                )
                self.replace_leaf_library(leaf, "live-legacy-lib-token")
                result = SHTEST.run_process(image, [], b"", 2, hierarchy)
                self.assertEqual(result.exit_status, 0)
                self.assertEqual(
                    base64.b64decode(result.stdout_b64),
                    b"captured-legacy-lib-token\n",
                )
            finally:
                image.close()

    def test_origin_runpath_shebang_interpreter_uses_captured_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            interpreter, library = self.build_origin_elf(
                directory, "interpreterfixture", "captured-interpreter", interpreter=True
            )
            script = directory / "candidate-script"
            script.write_text(f"#!{interpreter}\nignored\n", encoding="ascii")
            script.chmod(0o755)
            direct = subprocess.run(
                [str(script)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            self.assertEqual(direct.stdout, b"captured-interpreter\n")
            image = SHTEST.capture_executable(script, "candidate")
            baseline_fds = len(os.listdir("/proc/self/fd"))
            try:
                assert image.interpreter is not None
                self.assertEqual(len(image.interpreter.origin_dependencies), 1)
                self.replace_origin_library(
                    directory, "interpreterfixture", "host-replacement"
                )
                for _ in range(5):
                    result = SHTEST.run_process(image, [], b"", 2)
                    self.assertEqual(result.exit_status, 0)
                    self.assertEqual(
                        base64.b64decode(result.stdout_b64),
                        b"captured-interpreter\n",
                    )
                    self.assertFalse(result.cleanup_incomplete)
                    self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                library.unlink()
                result = SHTEST.run_process(image, [], b"", 2)
                self.assertEqual(result.exit_status, 0)
            finally:
                image.close()

    def test_renamed_tree_uses_captured_script_interpreter_and_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            hierarchy = root / "active"
            hierarchy.mkdir()
            interpreter, _ = self.build_origin_elf(
                hierarchy,
                "renameinterpreter",
                "captured-rename-tree",
                interpreter=True,
            )
            script = hierarchy / "candidate"
            script.write_text(f"#!{interpreter}\nignored\n", encoding="ascii")
            script.chmod(0o755)
            image = SHTEST.capture_executable(script, "candidate")
            retired = root / "retired"
            replacement = root / "replacement"
            replacement.mkdir()
            replacement_interpreter, _ = self.build_origin_elf(
                replacement,
                "renameinterpreter",
                "uncaptured-replacement-tree",
                interpreter=True,
            )
            replacement_script = replacement / "candidate"
            replacement_script.write_text(
                f"#!{hierarchy / replacement_interpreter.name}\nreplacement\n",
                encoding="ascii",
            )
            replacement_script.chmod(0o755)
            original_fork = SHTEST.fork_tracked_process
            exchanged = False

            def exchange_then_fork(*args: object, **kwargs: object) -> object:
                nonlocal exchanged
                self.assertFalse(exchanged)
                hierarchy.rename(retired)
                replacement.rename(hierarchy)
                exchanged = True
                return original_fork(*args, **kwargs)

            try:
                with mock.patch.object(
                    SHTEST,
                    "fork_tracked_process",
                    side_effect=exchange_then_fork,
                ):
                    result = SHTEST.run_process(image, [], b"", 2)
                self.assertTrue(exchanged)
                self.assertEqual(result.exit_status, 0)
                self.assertEqual(
                    base64.b64decode(result.stdout_b64),
                    b"captured-rename-tree\n",
                )
                self.assertNotIn(
                    b"uncaptured-replacement-tree",
                    base64.b64decode(result.stdout_b64),
                )
                self.assertFalse(result.cleanup_incomplete)
            finally:
                image.close()

    def test_recursive_origin_hierarchies_are_source_path_independent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            hierarchy = root / "native-tree"
            program, libraries = self.build_recursive_origin_elf(
                hierarchy, "recursivefixture", "sealed-recursive"
            )
            oracle = SHTEST.capture_executable(program, "oracle")
            candidate = SHTEST.capture_executable(program, "candidate")
            baseline_fds = len(os.listdir("/proc/self/fd"))
            staging_before = set(pathlib.Path("/dev/shm").glob(".shtest-path-launch-*"))
            retired = root / "native-tree-retired"
            hierarchy.rename(retired)
            self.build_recursive_origin_elf(
                hierarchy, "recursivefixture", "uncaptured-replacement"
            )
            try:
                for image in (oracle, candidate):
                    with self.subTest(role=image.label, phase="first"):
                        version = SHTEST.run_process(image, ["--version"], b"", 2)
                        self.assertEqual(
                            base64.b64decode(version.stdout_b64), b"jq-1.8.1\n"
                        )
                    exchanged = root / f"native-tree-{image.label}-replacement"
                    hierarchy.rename(exchanged)
                    self.build_recursive_origin_elf(
                        hierarchy, "recursivefixture", "second-uncaptured-replacement"
                    )
                    result = SHTEST.run_process(image, [], b"", 2)
                    self.assertEqual(result.exit_status, 0)
                    self.assertEqual(
                        base64.b64decode(result.stdout_b64), b"sealed-recursive\n"
                    )
                    self.assertFalse(result.cleanup_incomplete)
                    shutil.rmtree(exchanged)
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                self.assertEqual(
                    set(pathlib.Path("/dev/shm").glob(".shtest-path-launch-*")),
                    staging_before,
                )
                self.assertEqual(len(oracle.origin_dependencies), 2)
                self.assertEqual(
                    {item.path.name for item in oracle.origin_dependencies},
                    {path.name for path in libraries},
                )
            finally:
                oracle.close()
                candidate.close()

    def test_legacy_rpath_is_inherited_and_sealed_for_native_and_shebang(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            for interpreter in (False, True):
                with self.subTest(interpreter=interpreter):
                    hierarchy = root / ("shebang" if interpreter else "native")
                    program, libraries = self.build_transitive_search_elf(
                        hierarchy,
                        "legacyfixture",
                        "captured-legacy-leaf",
                        legacy_rpath=True,
                        interpreter=interpreter,
                    )
                    middle, leaf = libraries
                    program_tags = self.dynamic_tags(program)
                    middle_tags = self.dynamic_tags(middle)
                    self.assertIn("(RPATH)", program_tags)
                    self.assertNotIn("(RUNPATH)", program_tags)
                    self.assertNotIn("(RPATH)", middle_tags)
                    self.assertNotIn("(RUNPATH)", middle_tags)
                    executable = program
                    if interpreter:
                        executable = hierarchy / "candidate-script"
                        executable.write_text(f"#!{program}\nignored\n", encoding="ascii")
                        executable.chmod(0o755)
                    direct = subprocess.run(
                        [str(executable)],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    self.assertEqual(direct.stdout, b"captured-legacy-leaf\n")
                    image = SHTEST.capture_executable(executable, "candidate")
                    try:
                        native_image = image.interpreter if interpreter else image
                        assert native_image is not None
                        assert native_image.elf_interpreter is not None
                        self.assertEqual(
                            {dependency.path for dependency in native_image.origin_dependencies},
                            set(libraries),
                        )
                        report = SHTEST.executable_report(
                            executable, image, None, None
                        )
                        dependencies = (
                            report["interpreter"]["dependencies"]
                            if interpreter
                            else report["dependencies"]
                        )
                        self.assertEqual(
                            {entry["path"] for entry in dependencies},
                            {
                                *(str(path) for path in libraries),
                                str(native_image.elf_interpreter.path),
                            },
                        )
                        captured_leaf_hash = hashlib.sha256(leaf.read_bytes()).hexdigest()
                        self.replace_leaf_library(leaf, "live-replacement-leaf")
                        self.assertNotEqual(
                            hashlib.sha256(leaf.read_bytes()).hexdigest(),
                            captured_leaf_hash,
                        )
                        result = SHTEST.run_process(image, [], b"", 2, root)
                        self.assertEqual(result.exit_status, 0)
                        self.assertEqual(
                            base64.b64decode(result.stdout_b64),
                            b"captured-legacy-leaf\n",
                        )
                        self.assertFalse(result.cleanup_incomplete)
                    finally:
                        image.close()

    def test_runpath_is_not_inherited_by_untagged_middle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            hierarchy = pathlib.Path(temporary) / "runpath"
            program, libraries = self.build_transitive_search_elf(
                hierarchy,
                "runpathfixture",
                "must-not-be-found-transitively",
                legacy_rpath=False,
            )
            middle, leaf = libraries
            program_tags = self.dynamic_tags(program)
            middle_tags = self.dynamic_tags(middle)
            self.assertIn("(RUNPATH)", program_tags)
            self.assertNotIn("(RPATH)", program_tags)
            self.assertNotIn("(RPATH)", middle_tags)
            self.assertNotIn("(RUNPATH)", middle_tags)
            direct = subprocess.run(
                [str(program)], stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            self.assertNotEqual(direct.returncode, 0)
            image = SHTEST.capture_executable(program, "candidate")
            try:
                self.assertEqual(
                    [dependency.path for dependency in image.origin_dependencies],
                    [middle],
                )
                self.assertNotIn(
                    leaf,
                    {dependency.path for dependency in image.origin_dependencies},
                )
            finally:
                image.close()

    def test_recursive_shebang_hierarchy_survives_removal_and_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            hierarchy = root / "script-tree"
            interpreter, _ = self.build_recursive_origin_elf(
                hierarchy, "recursiveinterpreter", "sealed-interpreter",
                interpreter=True,
            )
            script = hierarchy / "scripts" / "candidate"
            script.parent.mkdir()
            script.write_text(f"#!{interpreter}\nignored\n", encoding="ascii")
            script.chmod(0o755)
            image = SHTEST.capture_executable(script, "candidate")
            retired = root / "script-tree-retired"
            hierarchy.rename(retired)
            replacement_interpreter, _ = self.build_recursive_origin_elf(
                hierarchy, "recursiveinterpreter", "uncaptured-interpreter",
                interpreter=True,
            )
            replacement_script = hierarchy / "scripts" / "candidate"
            replacement_script.parent.mkdir()
            replacement_script.write_text(
                f"#!{replacement_interpreter}\nreplacement\n", encoding="ascii"
            )
            replacement_script.chmod(0o755)
            try:
                version = SHTEST.run_process(image, ["--version"], b"", 2)
                self.assertEqual(base64.b64decode(version.stdout_b64), b"jq-1.8.1\n")
                shutil.rmtree(hierarchy)
                result = SHTEST.run_process(image, [], b"", 2)
                self.assertEqual(result.exit_status, 0)
                self.assertEqual(
                    base64.b64decode(result.stdout_b64), b"sealed-interpreter\n"
                )
                self.assertFalse(result.cleanup_incomplete)
            finally:
                image.close()

    def test_schema_v5_reports_stable_recursive_dependency_identities(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            native, native_libraries = self.build_recursive_origin_elf(
                root / "native", "reportnative", "native-report"
            )
            interpreter, interpreter_libraries = self.build_recursive_origin_elf(
                root / "script", "reportinterpreter", "interpreter-report",
                interpreter=True,
            )
            script = root / "script" / "candidate"
            script.write_text(f"#!{interpreter}\nignored\n", encoding="ascii")
            script.chmod(0o755)
            native_image = SHTEST.capture_executable(native, "oracle")
            script_image = SHTEST.capture_executable(script, "candidate")
            try:
                native_report = SHTEST.executable_report(
                    native, native_image, None, None
                )
                script_report = SHTEST.executable_report(
                    script, script_image, None, None
                )

                def expected(paths: tuple[pathlib.Path, ...]) -> list[dict[str, object]]:
                    return [
                        {
                            "path": str(path),
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                            "source_device": path.stat().st_dev,
                            "source_inode": path.stat().st_ino,
                        }
                        for path in sorted(paths, key=str)
                    ]

                assert native_image.elf_interpreter is not None
                self.assertEqual(
                    native_report["dependencies"],
                    expected((*native_libraries, native_image.elf_interpreter.path)),
                )
                self.assertIsNone(native_report["interpreter"])
                self.assertEqual(script_report["dependencies"], [])
                assert script_image.interpreter is not None
                assert script_image.interpreter.elf_interpreter is not None
                self.assertEqual(
                    script_report["interpreter"]["dependencies"],
                    expected(
                        (
                            *interpreter_libraries,
                            script_image.interpreter.elf_interpreter.path,
                        )
                    ),
                )
                self.assertEqual(SHTEST.REPORT_SCHEMA_VERSION, 5)
            finally:
                native_image.close()
                script_image.close()

    def test_missing_captured_origin_dependency_fails_as_setup_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            program, _ = self.build_origin_elf(
                directory, "missingfixture", "captured"
            )
            image = SHTEST.capture_executable(program, "candidate")
            assert image.origin_dependencies
            os.close(image.origin_dependencies[0].fd)
            image.origin_dependencies[0].fd = -1
            try:
                with self.assertRaises(SHTEST.ProcessSetupError) as raised:
                    SHTEST.run_process(image, [], b"", 2)
                self.assertEqual(raised.exception.step, "execution_image")
                self.assertFalse(raised.exception.timed_out)
                self.assertIsNone(raised.exception.result)
            finally:
                image.close()

    def test_missing_parent_authority_and_corrupt_clone_fail_boundedly(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            program, _ = self.build_origin_elf(
                directory, "authorityfixture", "captured"
            )
            missing_authority = SHTEST.capture_executable(program, "candidate")
            os.close(missing_authority.parent_fd)
            missing_authority.parent_fd = -1
            baseline_fds = len(os.listdir("/proc/self/fd"))
            try:
                started = time.monotonic()
                with self.assertRaises(SHTEST.ProcessSetupError) as raised:
                    SHTEST.run_process(missing_authority, [], b"", 2, directory)
                self.assertLess(time.monotonic() - started, 0.5)
                self.assertEqual(raised.exception.step, "execution_image")
                self.assertIsNone(raised.exception.result)
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                self.assertEqual(list(directory.glob("shtest-quarantine-*")), [])
            finally:
                missing_authority.close()

            corrupt = SHTEST.capture_executable(program, "candidate")
            dependency = corrupt.origin_dependencies[0]
            os.close(dependency.fd)
            flags = os.MFD_CLOEXEC | getattr(os, "MFD_ALLOW_SEALING", 0x0002)
            dependency.fd = os.memfd_create("shtest-corrupt-authority", flags)
            os.write(dependency.fd, b"uncaptured replacement bytes")
            baseline_fds = len(os.listdir("/proc/self/fd"))
            try:
                started = time.monotonic()
                with self.assertRaises(SHTEST.ProcessSetupError) as raised:
                    SHTEST.run_process(corrupt, [], b"", 2, directory)
                self.assertLess(time.monotonic() - started, 0.5)
                self.assertEqual(raised.exception.step, "origin_path_launch")
                self.assertIsNotNone(raised.exception.result)
                assert raised.exception.result is not None
                self.assertFalse(raised.exception.result.cleanup_incomplete)
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                self.assertEqual(list(directory.glob("shtest-quarantine-*")), [])
            finally:
                corrupt.close()

    def test_origin_dependency_capture_uses_cumulative_size_bound(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            program, library = self.build_origin_elf(
                directory, "boundedfixture", "captured"
            )
            combined = program.stat().st_size + library.stat().st_size
            with (
                mock.patch.object(
                    SHTEST, "MAX_EXECUTABLE_CAPTURE_BYTES", combined - 1
                ),
                self.assertRaisesRegex(
                    SHTEST.HarnessError, "origin dependencies exceed"
                ),
            ):
                SHTEST.capture_executable(program, "candidate")

    def test_origin_path_setup_stall_is_bounded_and_cleaned(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            program, _ = self.build_origin_elf(
                parent, "stallfixture", "captured"
            )
            image = SHTEST.capture_executable(program, "candidate")
            runner_pid = os.getpid()
            marker = parent / "origin-setup.pid"
            baseline_fds = len(os.listdir("/proc/self/fd"))

            def stalled_prepare(*args: object, **kwargs: object) -> None:
                if os.getpid() != runner_pid:
                    marker.write_text(str(os.getpid()), encoding="ascii")
                    time.sleep(60)

            try:
                started = time.monotonic()
                with (
                    mock.patch.object(SHTEST, "PROCESS_SETUP_SECONDS", 0.05),
                    mock.patch.object(
                        SHTEST,
                        "prepare_path_launches",
                        side_effect=stalled_prepare,
                    ),
                    self.assertRaises(SHTEST.ProcessSetupError) as raised,
                ):
                    SHTEST.run_process(image, [], b"", 2, parent)
                elapsed = time.monotonic() - started
                self.assertTrue(raised.exception.timed_out)
                self.assertEqual(raised.exception.step, "child_setup")
                self.assertIsNotNone(raised.exception.result)
                assert raised.exception.result is not None
                self.assertFalse(raised.exception.result.cleanup_incomplete)
                self.assertEqual(
                    base64.b64decode(raised.exception.result.stdout_b64), b""
                )
                self.assertEqual(
                    base64.b64decode(raised.exception.result.stderr_b64), b""
                )
                self.assertLess(elapsed, 0.5)
                setup_pid = int(marker.read_text(encoding="ascii"))
                self.assertFalse(pathlib.Path(f"/proc/{setup_pid}").exists())
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])
            finally:
                image.close()

    def make_cli(
        self,
        directory: pathlib.Path,
        name: str,
        mode: str = "pass",
        version: str = "jq-1.8.1",
        target: pathlib.Path | None = None,
        interpreter: pathlib.Path | None = None,
    ) -> pathlib.Path:
        path = directory / name
        path.write_text(
            FAKE_CLI.format(
                interpreter=str(interpreter or pathlib.Path(sys.executable).resolve()),
                mode=mode,
                version=version,
                target=str(target) if target is not None else "",
            ),
            encoding="utf-8",
        )
        path.chmod(0o755)
        return path

    def run_harness(
        self,
        cases: list[dict[str, object]],
        candidate_mode: str = "pass",
        *,
        oracle_mode: str = "pass",
        oracle_version: str = "jq-1.8.1",
        candidate_version: str = "jq-1.8.1",
        patterns: list[str] | None = None,
        candidate_target: pathlib.Path | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, object], pathlib.Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = pathlib.Path(temporary.name)
        catalog = directory / "catalog.json"
        catalog.write_text(json.dumps({"schema_version": 1, "cases": cases}), encoding="utf-8")
        oracle_interpreter = pathlib.Path(sys.executable).resolve()
        candidate_interpreter = pathlib.Path(sys.executable).resolve()
        if candidate_mode == "replace-interpreter":
            interpreter_temporary = tempfile.TemporaryDirectory()
            self.addCleanup(interpreter_temporary.cleanup)
            interpreter_directory = pathlib.Path(interpreter_temporary.name)
            oracle_interpreter = interpreter_directory / "oracle-python"
            candidate_interpreter = interpreter_directory / "candidate-python"
            shutil.copyfile(pathlib.Path(sys.executable).resolve(), oracle_interpreter)
            shutil.copyfile(pathlib.Path(sys.executable).resolve(), candidate_interpreter)
            oracle_interpreter.chmod(0o755)
            candidate_interpreter.chmod(0o755)
            candidate_target = candidate_interpreter
        oracle = self.make_cli(
            directory,
            "oracle",
            oracle_mode,
            oracle_version,
            interpreter=oracle_interpreter,
        )
        if candidate_mode == "self-replace":
            candidate_target = directory / "candidate"
        candidate = self.make_cli(
            directory,
            "candidate",
            candidate_mode,
            candidate_version,
            target=oracle if candidate_mode == "clobber" else candidate_target,
            interpreter=candidate_interpreter,
        )
        self.candidate_original_bytes = candidate.read_bytes()
        self.candidate_original_sha256 = hashlib.sha256(
            self.candidate_original_bytes
        ).hexdigest()
        report = directory / "report.json"
        command = [
            sys.executable,
            str(RUNNER),
            "--catalog",
            str(catalog),
            "--oracle",
            str(oracle),
            "--candidate",
            str(candidate),
            "--json-report",
            str(report),
        ]
        for pattern in patterns or []:
            command.extend(["--case", pattern])
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        parsed = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
        return completed, parsed, directory

    def run_harness_with_synchronized_host_replacement(
        self, *, replace_interpreter: bool
    ) -> tuple[
        int,
        dict[str, object],
        pathlib.Path,
        bytes,
        bytes,
        list[str],
    ]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = pathlib.Path(temporary.name)
        synchronization_temporary = tempfile.TemporaryDirectory()
        self.addCleanup(synchronization_temporary.cleanup)
        synchronization_directory = pathlib.Path(synchronization_temporary.name)

        catalog = directory / "catalog.json"
        catalog.write_text(
            json.dumps({"schema_version": 1, "cases": [run_case()]}),
            encoding="utf-8",
        )
        oracle = self.make_cli(directory, "oracle")
        candidate_interpreter = pathlib.Path(sys.executable).resolve()
        if replace_interpreter:
            candidate_interpreter = directory / "candidate-python"
            shutil.copyfile(pathlib.Path(sys.executable).resolve(), candidate_interpreter)
            candidate_interpreter.chmod(0o755)
        candidate = self.make_cli(
            directory,
            "candidate",
            interpreter=candidate_interpreter,
        )
        target = candidate_interpreter if replace_interpreter else candidate
        original_bytes = target.read_bytes()
        original_sha256 = hashlib.sha256(original_bytes).hexdigest()
        if replace_interpreter:
            replacement_bytes = pathlib.Path("/bin/false").read_bytes()
        else:
            replacement_bytes = (
                b"#!/bin/sh\nprintf 'host-replacement-must-not-execute\\n'\n"
            )
        self.assertNotEqual(
            hashlib.sha256(replacement_bytes).hexdigest(), original_sha256
        )

        ready_fifo = synchronization_directory / "namespace-ready"
        release_fifo = synchronization_directory / "host-replaced"
        os.mkfifo(ready_fifo, mode=0o600)
        os.mkfifo(release_fifo, mode=0o600)
        replacement = directory / f"{target.name}.host-replacement"
        handshake: list[str] = []
        replacement_errors: list[BaseException] = []

        def replace_host_path() -> None:
            release = b"replacement-failed"
            try:
                with ready_fifo.open("rb", buffering=0) as ready:
                    self.assertEqual(ready.read(), b"namespace-ready")
                handshake.append("namespace-ready")
                replacement.write_bytes(replacement_bytes)
                replacement.chmod(0o755)
                os.replace(replacement, target)
                self.assertEqual(target.read_bytes(), replacement_bytes)
                handshake.append("host-replaced")
                release = b"host-replaced"
            except BaseException as exc:
                replacement_errors.append(exc)
            finally:
                with release_fifo.open("wb", buffering=0) as released:
                    released.write(release)
                handshake.append("child-released")

        original_prepare = SHTEST.prepare_path_launches

        def prepare_and_wait_for_host_replacement(
            launches: tuple[object, ...],
        ) -> None:
            paths = {
                material.path
                for launch in launches
                for material in launch.materials
            }
            if candidate in paths and ready_fifo.exists():
                with ready_fifo.open("wb", buffering=0) as ready:
                    ready.write(b"namespace-ready")
                with release_fifo.open("rb", buffering=0) as released:
                    if released.read() != b"host-replaced":
                        raise OSError("host replacement handshake failed")
                ready_fifo.unlink()
                release_fifo.unlink()
            original_prepare(launches)

        replacer = threading.Thread(target=replace_host_path, daemon=True)
        replacer.start()
        report_path = directory / "report.json"
        with mock.patch.object(
            SHTEST,
            "prepare_path_launches",
            side_effect=prepare_and_wait_for_host_replacement,
        ):
            status = SHTEST.main(
                [
                    "--catalog",
                    str(catalog),
                    "--oracle",
                    str(oracle),
                    "--candidate",
                    str(candidate),
                    "--json-report",
                    str(report_path),
                ]
            )
        replacer.join(timeout=5)
        self.assertFalse(replacer.is_alive(), "host replacer did not finish")
        if replacement_errors:
            raise replacement_errors[0]
        report = json.loads(report_path.read_text(encoding="utf-8"))
        return (
            status,
            report,
            target,
            original_bytes,
            replacement_bytes,
            handshake,
        )

    def test_identical_success_and_exact_binary_streams_pass(self) -> None:
        completed, report, _ = self.run_harness(
            [run_case("success", ["success"]), run_case("binary", ["binary"], b"\x00\xffstdin")]
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(
            report["summary"],
            {"selected": 2, "passed": 2, "failed": 0, "skipped": 0, "errors": 0},
        )
        binary = report["cases"][1]
        self.assertEqual(base64.b64decode(binary["oracle"]["stdout_b64"]), b"\x00\xff\x00\xffstdin")
        self.assertEqual(base64.b64decode(binary["oracle"]["stderr_b64"]), b"\xfeerr\x00")
        for role in ("oracle", "candidate"):
            self.assertFalse(binary[role]["descendant_cleanup_required"])
            self.assertFalse(report[role]["version_process"]["descendant_cleanup_required"])

    def test_huge_catalog_timeout_is_a_structured_catalog_error(self) -> None:
        completed, report, _ = self.run_harness(
            [run_case(timeout=10**400)]
        )
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        self.assertNotIn("Traceback", completed.stderr)
        self.assertIn("HARNESS ERROR", completed.stderr)
        self.assertEqual(report["schema_version"], 5)
        self.assertEqual(
            report["summary"],
            {"selected": 0, "passed": 0, "failed": 0, "skipped": 0, "errors": 1},
        )
        self.assertEqual(report["cases"], [])
        self.assertEqual(report["startup_failure"]["stage"], "catalog")
        self.assertIsNone(report["startup_failure"]["role"])
        self.assertIsNone(report["startup_failure"]["process_result"])
        self.assertIn(
            "case 1.timeout_seconds: must be greater than zero and at most 60",
            report["startup_failure"]["message"],
        )

    def test_special_and_symlink_executable_paths_are_promptly_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            oracle = self.make_cli(directory, "oracle")
            marker = directory / "hostile-executed"
            hostile = directory / "hostile"
            hostile.write_text(
                "#!/bin/sh\nprintf executed > " + str(marker) + "\n",
                encoding="utf-8",
            )
            hostile.chmod(0o755)

            fifo_without_writer = directory / "fifo-no-writer"
            fifo_with_writer = directory / "fifo-with-writer"
            os.mkfifo(fifo_without_writer, 0o755)
            os.mkfifo(fifo_with_writer, 0o755)
            writer_fd = os.open(fifo_with_writer, os.O_RDWR | os.O_NONBLOCK)
            symlink = directory / "candidate-symlink"
            symlink.symlink_to(hostile)
            socket_path = directory / "candidate-socket"
            listener = socket.socket(socket.AF_UNIX)
            listener.bind(str(socket_path))
            candidates = {
                "fifo without writer": fifo_without_writer,
                "fifo with writer": fifo_with_writer,
                "symlink": symlink,
                "socket": socket_path,
                "device": pathlib.Path("/dev/null"),
            }
            try:
                for repetition in range(2):
                    for label, candidate in candidates.items():
                        with self.subTest(label=label, repetition=repetition):
                            report_path = directory / f"report-{repetition}.json"
                            started = time.monotonic()
                            completed = subprocess.run(
                                [
                                    sys.executable,
                                    str(RUNNER),
                                    "--catalog",
                                    str(catalog),
                                    "--oracle",
                                    str(oracle),
                                    "--candidate",
                                    str(candidate),
                                    "--json-report",
                                    str(report_path),
                                ],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                                text=True,
                                check=False,
                                timeout=3,
                            )
                            self.assertLess(time.monotonic() - started, 2)
                            self.assertEqual(completed.returncode, 2)
                            report = json.loads(report_path.read_text(encoding="utf-8"))
                            failure = report["startup_failure"]
                            self.assertEqual(failure["stage"], "executable_capture")
                            self.assertEqual(failure["role"], "candidate")
                            self.assertIsNone(failure["process_result"])
                            self.assertRegex(
                                failure["message"],
                                "symlink|not an executable regular file",
                            )
                            self.assertFalse(marker.exists())
            finally:
                os.close(writer_fd)
                listener.close()

    def test_executable_capture_size_and_deadline_are_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            oversized = directory / "oversized"
            with oversized.open("wb") as output:
                output.truncate(SHTEST.MAX_EXECUTABLE_CAPTURE_BYTES + 1)
            oversized.chmod(0o755)
            with self.assertRaisesRegex(SHTEST.HarnessError, "capture limit"):
                SHTEST.capture_executable(oversized, "candidate")

            executable = self.make_cli(directory, "deadline-candidate")
            executable_identity = executable.stat()
            real_read = os.read

            def slow_source_read(descriptor: int, count: int) -> bytes:
                identity = os.fstat(descriptor)
                if (identity.st_dev, identity.st_ino) == (
                    executable_identity.st_dev,
                    executable_identity.st_ino,
                ):
                    time.sleep(0.05)
                return real_read(descriptor, count)

            with (
                mock.patch.object(SHTEST, "EXECUTABLE_CAPTURE_SECONDS", 0.01),
                mock.patch.object(SHTEST.os, "read", side_effect=slow_source_read),
            ):
                with self.assertRaisesRegex(SHTEST.HarnessError, "capture exceeded"):
                    SHTEST.capture_executable(executable, "candidate")

    def test_capture_alarm_bounds_initial_open_and_restores_prior_timer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            executable = self.make_cli(directory, "blocked-open")
            real_open = os.open
            baseline_fds = len(os.listdir("/proc/self/fd"))
            prior_handler = signal.getsignal(signal.SIGALRM)
            prior_timer = signal.getitimer(signal.ITIMER_REAL)

            def prior_alarm(signum: int, frame: object) -> None:
                del signum, frame

            def blocked_open(
                path: object, flags: int, *args: object, **kwargs: object
            ) -> int:
                if pathlib.Path(path) == executable:
                    time.sleep(60)
                return real_open(path, flags, *args, **kwargs)

            try:
                signal.signal(signal.SIGALRM, prior_alarm)
                signal.setitimer(signal.ITIMER_REAL, 30.0, 7.0)
                started = time.monotonic()
                with (
                    mock.patch.object(SHTEST, "EXECUTABLE_CAPTURE_SECONDS", 0.03),
                    mock.patch.object(SHTEST.os, "open", side_effect=blocked_open),
                    self.assertRaisesRegex(SHTEST.HarnessError, "capture exceeded"),
                ):
                    SHTEST.capture_executable(executable, "candidate")
                self.assertLess(time.monotonic() - started, 0.2)
                self.assertIs(signal.getsignal(signal.SIGALRM), prior_alarm)
                restored_timer = signal.getitimer(signal.ITIMER_REAL)
                self.assertGreater(restored_timer[0], 29.8)
                self.assertEqual(restored_timer[1], 7.0)
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                self.assertEqual(list(directory.glob("shtest-quarantine-*")), [])
            finally:
                signal.setitimer(signal.ITIMER_REAL, 0)
                signal.signal(signal.SIGALRM, prior_handler)
                signal.setitimer(signal.ITIMER_REAL, *prior_timer)

    def test_capture_alarm_independently_bounds_dependency_lookup_and_open(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            program, library = self.build_origin_elf(
                directory, "dependencydeadline", "captured"
            )
            baseline_fds = len(os.listdir("/proc/self/fd"))
            real_is_file = pathlib.Path.is_file
            real_open = os.open

            def blocked_lookup(path: pathlib.Path) -> bool:
                if path == library:
                    time.sleep(60)
                return real_is_file(path)

            def blocked_open(
                path: object, flags: int, *args: object, **kwargs: object
            ) -> int:
                if pathlib.Path(path) == library:
                    time.sleep(60)
                return real_open(path, flags, *args, **kwargs)

            for phase, owner, attribute, side_effect in (
                ("lookup", pathlib.Path, "is_file", blocked_lookup),
                ("open", SHTEST.os, "open", blocked_open),
            ):
                with (
                    self.subTest(phase=phase),
                    mock.patch.object(SHTEST, "EXECUTABLE_CAPTURE_SECONDS", 0.03),
                    mock.patch.object(
                        owner,
                        attribute,
                        autospec=phase == "lookup",
                        side_effect=side_effect,
                    ),
                    self.assertRaisesRegex(SHTEST.HarnessError, "capture exceeded"),
                ):
                    started = time.monotonic()
                    SHTEST.capture_executable(program, "candidate")
                self.assertLess(time.monotonic() - started, 0.2)
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))

    def test_blocked_executable_read_has_wall_clock_bound_and_structured_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            report_path = directory / "report.json"
            candidate = directory / "candidate"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            shutil.copyfile(pathlib.Path(sys.executable).resolve(), candidate)
            candidate.chmod(0o755)
            candidate_identity = candidate.stat()
            real_read = os.read

            def blocking_candidate_read(descriptor: int, count: int) -> bytes:
                identity = os.fstat(descriptor)
                if (identity.st_dev, identity.st_ino) == (
                    candidate_identity.st_dev,
                    candidate_identity.st_ino,
                ):
                    time.sleep(0.20)
                return real_read(descriptor, count)

            baseline_fds = len(os.listdir("/proc/self/fd"))
            baseline_children = SHTEST.descendant_baseline()
            baseline_alarm_handler = signal.getsignal(signal.SIGALRM)
            baseline_alarm_timer = signal.getitimer(signal.ITIMER_REAL)
            started = time.monotonic()
            with (
                mock.patch.object(SHTEST, "EXECUTABLE_CAPTURE_SECONDS", 0.05),
                mock.patch.object(SHTEST.os, "read", side_effect=blocking_candidate_read),
                mock.patch.object(SHTEST.subprocess, "Popen") as popen,
                mock.patch("builtins.print") as printed,
            ):
                status = SHTEST.main(
                    [
                        "--catalog",
                        str(catalog),
                        "--oracle",
                        str(pathlib.Path(sys.executable).resolve()),
                        "--candidate",
                        str(candidate),
                        "--json-report",
                        str(report_path),
                    ]
                )
            elapsed = time.monotonic() - started

            self.assertLess(elapsed, 0.15)
            self.assertEqual(status, 2)
            popen.assert_not_called()
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["schema_version"], 5)
            self.assertEqual(report["startup_failure"]["stage"], "executable_capture")
            self.assertEqual(report["startup_failure"]["role"], "candidate")
            self.assertIsNone(report["startup_failure"]["process_result"])
            self.assertIn("capture exceeded", report["startup_failure"]["message"])
            self.assertNotIn("Traceback", " ".join(str(call) for call in printed.call_args_list))
            self.assertEqual(SHTEST.descendant_baseline(), baseline_children)
            self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
            self.assertEqual(signal.getsignal(signal.SIGALRM), baseline_alarm_handler)
            self.assertEqual(signal.getitimer(signal.ITIMER_REAL), baseline_alarm_timer)
            self.assertEqual(list(directory.glob("shtest-quarantine-*")), [])

    def test_shebang_capture_rejects_unbound_argument_and_relative_interpreter(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            cases = (
                (f"#!{pathlib.Path(sys.executable).resolve()} -S\n", "arguments"),
                ("#!relative-python\n", "absolute"),
            )
            for index, (header, message) in enumerate(cases):
                with self.subTest(header=header):
                    script = directory / f"candidate-{index}"
                    script.write_text(header + "raise SystemExit(0)\n", encoding="utf-8")
                    script.chmod(0o755)
                    image = None
                    try:
                        with self.assertRaisesRegex(SHTEST.HarnessError, message):
                            image = SHTEST.capture_executable(script, "candidate")
                    finally:
                        if image is not None:
                            image.close()

    def test_shebang_execution_preserves_script_path_and_sibling_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            script = directory / "candidate"
            sibling = directory / "candidate-resource"
            sibling.write_text("sibling-data", encoding="utf-8")
            script.write_text(
                f"#!{pathlib.Path(sys.executable).resolve()}\n"
                "import pathlib, sys\n"
                "script = pathlib.Path(__file__)\n"
                "sys.stdout.write(str(script) + '\\n')\n"
                "sys.stdout.write(script.with_name('candidate-resource').read_text())\n",
                encoding="utf-8",
            )
            script.chmod(0o755)
            image = SHTEST.capture_executable(script, "candidate")
            try:
                result = SHTEST.run_process(image, [], b"", 2)
            finally:
                image.close()

        self.assertEqual(result.exit_status, 0)
        self.assertEqual(result.signal, None)
        self.assertFalse(result.cleanup_incomplete)
        self.assertEqual(
            base64.b64decode(result.stdout_b64),
            f"{script}\nsibling-data".encode(),
        )

    def assert_linux_shebang_control_byte_fails_closed(self, separator: bytes) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            oracle = self.make_cli(directory, "oracle")
            marker = directory / "candidate-executed"
            candidate = directory / "candidate"
            candidate.write_bytes(
                b"#!"
                + os.fsencode(pathlib.Path(sys.executable).resolve())
                + separator
                + b"\n"
                + (
                    "import pathlib, sys\n"
                    f"pathlib.Path({str(marker)!r}).write_bytes(b'executed')\n"
                    "if sys.argv[1:] == ['--version']:\n"
                    "    print('jq-1.8.1')\n"
                    "    raise SystemExit(0)\n"
                    "sys.stdout.buffer.write(b'out\\x00\\xff')\n"
                    "sys.stderr.buffer.write(b'err\\xfe')\n"
                ).encode("utf-8")
            )
            candidate.chmod(0o755)

            with self.assertRaises(FileNotFoundError) as direct_failure:
                subprocess.run(
                    [str(candidate), "--version"],
                    check=False,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
            self.assertEqual(direct_failure.exception.errno, 2)
            self.assertFalse(marker.exists())

            report_path = directory / "report.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER),
                    "--catalog",
                    str(catalog),
                    "--oracle",
                    str(oracle),
                    "--candidate",
                    str(candidate),
                    "--json-report",
                    str(report_path),
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(report["schema_version"], 5)
            self.assertEqual(
                report["summary"],
                {"selected": 1, "passed": 0, "failed": 0, "skipped": 0, "errors": 1},
            )
            self.assertEqual(report["cases"], [])
            self.assertEqual(report["startup_failure"]["stage"], "executable_capture")
            self.assertEqual(report["startup_failure"]["role"], "candidate")
            self.assertIsNone(report["startup_failure"]["process_result"])
            self.assertIn("invalid", report["startup_failure"]["message"])
            self.assertFalse(marker.exists())

    def test_vertical_tab_is_not_a_linux_shebang_separator(self) -> None:
        self.assert_linux_shebang_control_byte_fails_closed(b"\x0b")

    def test_form_feed_is_not_a_linux_shebang_separator(self) -> None:
        self.assert_linux_shebang_control_byte_fails_closed(b"\x0c")

    def test_exact_stdout_and_stderr_mismatches_are_separate(self) -> None:
        for mode, expected in (("stdout-mismatch", "stdout bytes differ"), ("stderr-mismatch", "stderr bytes differ")):
            with self.subTest(mode=mode):
                completed, report, _ = self.run_harness([run_case()], mode)
                self.assertEqual(completed.returncode, 1)
                self.assertIn(expected, report["cases"][0]["differences"])

    def test_descendant_cleanup_evidence_is_compared_explicitly(self) -> None:
        def result(required: bool) -> object:
            return SHTEST.ProcessResult(
                argv=["sealed", "success"],
                working_directory="/tmp/removed",
                exit_status=0,
                signal=None,
                timed_out=False,
                duration_ms=1,
                stdout_b64=b64(b"same"),
                stderr_b64=b64(b""),
                stdout_truncated=False,
                stderr_truncated=False,
                output_limit_exceeded=False,
                pipe_drain_timed_out=False,
                descendant_cleanup_required=required,
                cleanup_incomplete=False,
            )

        self.assertEqual(SHTEST.compare_results(result(False), result(False)), [])
        self.assertIn(
            "descendant cleanup requirement differs: oracle=False, candidate=True",
            SHTEST.compare_results(result(False), result(True)),
        )
        self.assertIn(
            "descendant cleanup requirement differs: oracle=True, candidate=False",
            SHTEST.compare_results(result(True), result(False)),
        )

    def test_exit_status_and_signal_termination_are_distinct(self) -> None:
        completed, report, _ = self.run_harness([run_case(argv=["exit"])], "exit-mismatch")
        self.assertEqual(completed.returncode, 1)
        self.assertIn("exit status differs: oracle=7, candidate=9", report["cases"][0]["differences"])

        completed, report, _ = self.run_harness([run_case(argv=["exit"])], "signal")
        self.assertEqual(completed.returncode, 1)
        candidate = report["cases"][0]["candidate"]
        self.assertIsNone(candidate["exit_status"])
        self.assertEqual(candidate["signal"], signal.SIGTERM)

    def test_partial_output_is_kept_before_failure(self) -> None:
        completed, report, _ = self.run_harness([run_case(argv=["exit"])])
        self.assertEqual(completed.returncode, 0)
        result = report["cases"][0]["candidate"]
        self.assertEqual(base64.b64decode(result["stdout_b64"]), b"partial-out")
        self.assertEqual(base64.b64decode(result["stderr_b64"]), b"partial-err")
        self.assertEqual(result["exit_status"], 7)

    def test_timeout_keeps_partial_output_kills_descendant_and_cleans_directory(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        marker = pathlib.Path(temporary.name) / "descendant.pid"
        case = run_case(argv=["success"], timeout=0.2)
        completed, report, _ = self.run_harness(
            [case], "hang-candidate", candidate_target=marker
        )
        self.assertEqual(completed.returncode, 1)
        result = report["cases"][0]["candidate"]
        self.assertTrue(result["timed_out"])
        self.assertEqual(base64.b64decode(result["stdout_b64"]), b"before-timeout-out\xff")
        self.assertEqual(base64.b64decode(result["stderr_b64"]), b"before-timeout-err\xfe")
        self.assertFalse(pathlib.Path(result["working_directory"]).exists())
        descendant, process_group = map(
            int, marker.read_text(encoding="ascii").split()
        )
        self.assertFalse(pathlib.Path(f"/proc/{descendant}").exists())
        with self.assertRaises(ProcessLookupError):
            os.killpg(process_group, 0)

    def test_slow_setup_preserves_full_post_launch_allowance_symmetrically(self) -> None:
        images = [
            SHTEST.capture_executable(
                pathlib.Path(sys.executable).resolve(), role
            )
            for role in ("oracle", "candidate")
        ]
        original_baseline = SHTEST.descendant_baseline
        setup_delays = iter((0.02, 0.20))

        def slow_baseline() -> set[tuple[int, int]]:
            time.sleep(next(setup_delays))
            return original_baseline()

        try:
            with tempfile.TemporaryDirectory() as temporary:
                parent = pathlib.Path(temporary)
                with mock.patch.object(
                    SHTEST, "descendant_baseline", side_effect=slow_baseline
                ):
                    results = [
                        SHTEST.run_process(
                            image,
                            ["-c", "import time; time.sleep(0.08)"],
                            b"",
                            0.30,
                            parent,
                        )
                        for image in images
                    ]
                for result in results:
                    self.assertFalse(result.timed_out)
                    self.assertEqual(result.exit_status, 0)
                    self.assertFalse(result.cleanup_incomplete)
                    self.assertFalse(pathlib.Path(result.working_directory).exists())
                self.assertGreater(results[1].duration_ms, 250)
                self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])
        finally:
            for image in images:
                image.close()

    def test_exec_observation_timestamp_survives_parent_delay_for_all_launches(
        self,
    ) -> None:
        real_await = SHTEST.await_child_setup
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            baseline_fds = len(os.listdir("/proc/self/fd"))
            for role in ("oracle", "candidate"):
                for shebang in (False, True):
                    for expected_timeout in (False, True):
                        with self.subTest(
                            role=role,
                            shebang=shebang,
                            expected_timeout=expected_timeout,
                        ):
                            if expected_timeout:
                                code = (
                                    "import sys,time; "
                                    "sys.stdout.write('partial-after-exec\\n'); "
                                    "sys.stdout.flush(); time.sleep(60)"
                                )
                                timeout = 0.03
                                parent_delay = 0.08
                            else:
                                code = (
                                    "import sys,time; "
                                    "sys.stdout.write('complete-after-exec\\n'); "
                                    "sys.stdout.flush(); time.sleep(0.03)"
                                )
                                timeout = 0.20
                                parent_delay = 0.02

                            if shebang:
                                target = parent / (
                                    f"{role}-{'timeout' if expected_timeout else 'success'}"
                                )
                                target.write_text(
                                    f"#!{pathlib.Path(sys.executable).resolve()}\n{code}\n",
                                    encoding="utf-8",
                                )
                                target.chmod(0o755)
                                image = SHTEST.capture_executable(target, role)
                                arguments: list[str] = []
                            else:
                                image = SHTEST.capture_executable(
                                    pathlib.Path(sys.executable).resolve(), role
                                )
                                arguments = ["-c", code]

                            observed_at: list[float] = []

                            def delayed_after_exec(
                                *args: object, **kwargs: object
                            ) -> object:
                                outcome = real_await(*args, **kwargs)
                                assert outcome.execution_started is not None
                                observed_at.append(outcome.execution_started)
                                time.sleep(parent_delay)
                                return outcome

                            try:
                                with mock.patch.object(
                                    SHTEST,
                                    "await_child_setup",
                                    side_effect=delayed_after_exec,
                                ):
                                    result = SHTEST.run_process(
                                        image, arguments, b"", timeout, parent
                                    )
                                self.assertEqual(result.timed_out, expected_timeout)
                                self.assertFalse(result.cleanup_incomplete)
                                self.assertFalse(
                                    pathlib.Path(result.working_directory).exists()
                                )
                                expected_output = (
                                    b"partial-after-exec\n"
                                    if expected_timeout
                                    else b"complete-after-exec\n"
                                )
                                self.assertEqual(
                                    base64.b64decode(result.stdout_b64), expected_output
                                )
                                self.assertEqual(len(observed_at), 1)
                            finally:
                                image.close()
                            self.assertEqual(
                                len(os.listdir("/proc/self/fd")), baseline_fds
                            )
            self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])

    def test_setup_timeout_before_launch_is_structured_and_leak_free(self) -> None:
        image = SHTEST.capture_executable(
            pathlib.Path(sys.executable).resolve(), "candidate"
        )
        baseline_fds = len(os.listdir("/proc/self/fd"))
        try:
            with tempfile.TemporaryDirectory() as temporary:
                parent = pathlib.Path(temporary)
                with (
                    mock.patch.object(SHTEST, "PROCESS_SETUP_SECONDS", 0.05),
                    mock.patch.object(
                        SHTEST,
                        "descendant_baseline",
                        side_effect=lambda: (time.sleep(0.08), set())[1],
                    ),
                    mock.patch.object(SHTEST, "fork_tracked_process") as launch,
                    self.assertRaises(SHTEST.ProcessSetupError) as raised,
                ):
                    SHTEST.run_process(image, [], b"", 1, parent)
                self.assertTrue(raised.exception.timed_out)
                self.assertEqual(
                    raised.exception.report_stage, "process_setup_timeout"
                )
                self.assertEqual(raised.exception.role, "candidate")
                self.assertEqual(raised.exception.step, "descendant_baseline")
                launch.assert_not_called()
                self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
        finally:
            image.close()

    def test_native_exec_setup_stall_is_bounded_and_leak_free(self) -> None:
        image = SHTEST.capture_executable(
            pathlib.Path(sys.executable).resolve(), "oracle"
        )
        real_execve = SHTEST.os.execve
        runner_pid = os.getpid()
        baseline_fds = len(os.listdir("/proc/self/fd"))
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            marker = parent / "launched.pid"

            def stalled_execve(*args: object, **kwargs: object) -> None:
                if os.getpid() != runner_pid:
                    marker.write_text(str(os.getpid()), encoding="ascii")
                    time.sleep(60)
                real_execve(*args, **kwargs)

            try:
                started = time.monotonic()
                with (
                    mock.patch.object(SHTEST, "PROCESS_SETUP_SECONDS", 0.05),
                    mock.patch.object(SHTEST.os, "execve", side_effect=stalled_execve),
                    self.assertRaises(SHTEST.ProcessSetupError) as raised,
                ):
                    SHTEST.run_process(image, ["-c", "raise SystemExit(0)"], b"", 1, parent)
                elapsed = time.monotonic() - started
                self.assertTrue(raised.exception.timed_out)
                self.assertEqual(raised.exception.report_stage, "process_setup_timeout")
                self.assertEqual(raised.exception.step, "child_setup")
                self.assertIsNotNone(raised.exception.result)
                assert raised.exception.result is not None
                self.assertFalse(raised.exception.result.cleanup_incomplete)
                self.assertIsNone(raised.exception.result.quarantined_path)
                self.assertLess(elapsed, 0.5)
                launched_pid = int(marker.read_text(encoding="ascii"))
                self.assertFalse(pathlib.Path(f"/proc/{launched_pid}").exists())
                self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
            finally:
                image.close()

    def test_shebang_copy_setup_timeout_interrupts_after_copy_progress(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            script = parent / "large-candidate"
            header = (
                f"#!{pathlib.Path(sys.executable).resolve()}\n"
                "raise SystemExit(0)\n#"
            ).encode("ascii")
            script.write_bytes(header + b"x" * (2 * 1024 * 1024 - len(header)))
            script.chmod(0o755)
            image = SHTEST.capture_executable(script, "candidate")
            notify_read, notify_write = os.pipe()
            release_read, release_write = os.pipe()
            observed_read, observed_write = os.pipe()
            controller = self.delayed_pipe_release(
                notify_read,
                notify_write,
                release_read,
                release_write,
                observed_read,
                observed_write,
                0.75,
            )
            original_pread = SHTEST.os.pread
            original_close_child_descriptors = SHTEST.close_child_descriptors
            runner_pid = os.getpid()
            blocked = False

            def block_after_first_mebibyte(
                descriptor: int, size: int, offset: int
            ) -> bytes:
                nonlocal blocked
                if os.getpid() != runner_pid and offset >= 1024 * 1024 and not blocked:
                    blocked = True
                    os.write(notify_write, str(os.getpid()).encode("ascii"))
                    os.read(release_read, 1)
                return original_pread(descriptor, size, offset)

            def keep_blocker_descriptors(keep: set[int]) -> None:
                original_close_child_descriptors(keep | {notify_write, release_read})

            started = time.monotonic()
            try:
                with (
                    mock.patch.object(SHTEST, "PROCESS_SETUP_SECONDS", 0.05),
                    mock.patch.object(SHTEST.os, "pread", side_effect=block_after_first_mebibyte),
                    mock.patch.object(
                        SHTEST,
                        "close_child_descriptors",
                        side_effect=keep_blocker_descriptors,
                    ),
                    mock.patch.object(
                        SHTEST.subprocess, "Popen", wraps=subprocess.Popen
                    ) as popen,
                    self.assertRaises(SHTEST.ProcessSetupError) as raised,
                ):
                    SHTEST.run_process(image, [], b"", 1, parent)
                elapsed = time.monotonic() - started
                child_pid = int(os.read(observed_read, 64))
                self.assertTrue(raised.exception.timed_out)
                self.assertEqual(raised.exception.report_stage, "process_setup_timeout")
                self.assertEqual(raised.exception.role, "candidate")
                self.assertEqual(raised.exception.step, "child_setup")
                self.assertIsNotNone(raised.exception.result)
                assert raised.exception.result is not None
                self.assertFalse(raised.exception.result.cleanup_incomplete)
                self.assertLessEqual(
                    len(base64.b64decode(raised.exception.result.stdout_b64)),
                    SHTEST.MAX_CAPTURE_BYTES,
                )
                self.assertLessEqual(
                    len(base64.b64decode(raised.exception.result.stderr_b64)),
                    SHTEST.MAX_CAPTURE_BYTES,
                )
                self.assertLess(elapsed, 0.5)
                popen.assert_not_called()
                self.assertFalse(pathlib.Path(f"/proc/{child_pid}").exists())
                self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])
            finally:
                for descriptor in (notify_write, release_read, observed_read):
                    os.close(descriptor)
                os.waitpid(controller, 0)
                image.close()

    def assert_setup_child_death_is_structured(self, terminating_signal: bool) -> None:
        stages = (
            ("session_creation", SHTEST.os, "setsid"),
            ("chdir", SHTEST.os, "chdir"),
            ("script_path_launch", SHTEST, "prepare_path_launches"),
            ("descriptor_closure", SHTEST.fcntl, "fcntl"),
            ("exec", SHTEST.os, "execve"),
        )
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            script = parent / "candidate"
            script.write_text(
                f"#!{pathlib.Path(sys.executable).resolve()}\nraise SystemExit(0)\n",
                encoding="utf-8",
            )
            script.chmod(0o755)
            image = SHTEST.capture_executable(script, "candidate")
            runner_pid = os.getpid()
            baseline_fds = len(os.listdir("/proc/self/fd"))
            baseline_alarm_handler = signal.getsignal(signal.SIGALRM)
            baseline_alarm_timer = signal.getitimer(signal.ITIMER_REAL)
            try:
                for stage, owner, attribute in stages:
                    original = getattr(owner, attribute)

                    def terminate_at_stage(*args: object, **kwargs: object) -> object:
                        if os.getpid() != runner_pid:
                            if terminating_signal:
                                os.kill(os.getpid(), signal.SIGKILL)
                                os._exit(92)
                            os._exit(91)
                        return original(*args, **kwargs)

                    with (
                        self.subTest(stage=stage),
                        mock.patch.object(
                            owner, attribute, side_effect=terminate_at_stage
                        ),
                        self.assertRaises(SHTEST.ProcessSetupError) as raised,
                    ):
                        SHTEST.run_process(image, [], b"", 1, parent)
                    self.assertFalse(raised.exception.timed_out)
                    self.assertEqual(raised.exception.step, stage)
                    self.assertIsNotNone(raised.exception.result)
                    assert raised.exception.result is not None
                    if terminating_signal:
                        self.assertIsNone(raised.exception.result.exit_status)
                        self.assertEqual(
                            raised.exception.result.signal, signal.SIGKILL
                        )
                    else:
                        self.assertEqual(raised.exception.result.exit_status, 91)
                        self.assertIsNone(raised.exception.result.signal)
                    self.assertFalse(raised.exception.result.cleanup_incomplete)
                    self.assertEqual(
                        list(parent.glob("shtest-quarantine-*")), []
                    )
                    self.assertEqual(
                        len(os.listdir("/proc/self/fd")), baseline_fds
                    )
                    self.assertEqual(
                        signal.getsignal(signal.SIGALRM), baseline_alarm_handler
                    )
                    self.assertEqual(
                        signal.getitimer(signal.ITIMER_REAL), baseline_alarm_timer
                    )
            finally:
                image.close()

    def test_setup_child_exit_is_structured_at_every_stage(self) -> None:
        self.assert_setup_child_death_is_structured(False)

    def test_setup_child_signal_is_structured_at_every_stage(self) -> None:
        self.assert_setup_child_death_is_structured(True)

    def test_repeated_shebang_launches_release_trace_and_descriptors(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            script = parent / "candidate"
            script.write_text(
                f"#!{pathlib.Path(sys.executable).resolve()}\nraise SystemExit(0)\n",
                encoding="utf-8",
            )
            script.chmod(0o755)
            image = SHTEST.capture_executable(script, "candidate")
            baseline_fds = len(os.listdir("/proc/self/fd"))
            baseline_children = SHTEST.descendant_baseline()
            try:
                for _ in range(20):
                    result = SHTEST.run_process(image, [], b"", 1, parent)
                    self.assertEqual(result.exit_status, 0)
                    self.assertFalse(result.cleanup_incomplete)
                    self.assertFalse(pathlib.Path(result.working_directory).exists())
                    self.assertEqual(
                        len(os.listdir("/proc/self/fd")), baseline_fds
                    )
                    self.assertEqual(
                        SHTEST.descendant_baseline(), baseline_children
                    )
            finally:
                image.close()

    def assert_reaped_forked_process_fails_closed(self, pid: int) -> None:
        process = SHTEST.ForkedProcess(pid, ["reaped-child"], None, None, None)
        with self.assertRaisesRegex(
            SHTEST.ProcessStatusError, "lost exclusive wait-status ownership"
        ):
            process.poll()
        for operation in (
            process.poll,
            process.wait,
            lambda: process.wait(timeout=0.01),
        ):
            with self.assertRaisesRegex(
                SHTEST.ProcessStatusError,
                "lost exclusive wait-status ownership",
            ):
                operation()

    def test_external_reap_never_maps_dead_child_to_live_or_timeout(self) -> None:
        pid = os.fork()
        if pid == 0:
            os._exit(23)
        identity = SHTEST.process_identity(pid)
        self.assertIsNotNone(identity)
        os.waitpid(pid, 0)
        process = SHTEST.ForkedProcess(pid, ["reaped-child"], None, None, None)
        with self.assertRaises(SHTEST.ProcessStatusError):
            process.poll()
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
        cleanup = SHTEST.terminate_process_tree(
            process, set(), identity, None, budget
        )
        self.assertTrue(cleanup.complete)
        self.assertFalse(cleanup.descendant_cleanup_required)
        self.assert_reaped_forked_process_fails_closed(pid)

    def test_adopted_reap_has_repeatable_closed_status_semantics(self) -> None:
        SHTEST.enable_child_subreaper()
        read_fd, write_fd = os.pipe2(os.O_CLOEXEC)
        intermediary = os.fork()
        if intermediary == 0:
            os.close(read_fd)
            adopted = os.fork()
            if adopted == 0:
                os.close(write_fd)
                os._exit(29)
            os.write(write_fd, str(adopted).encode("ascii"))
            os.close(write_fd)
            os._exit(0)
        os.close(write_fd)
        adopted_pid = int(os.read(read_fd, 64))
        os.close(read_fd)
        os.waitpid(intermediary, 0)
        os.waitpid(adopted_pid, 0)
        self.assert_reaped_forked_process_fails_closed(adopted_pid)

    def test_blocked_child_mount_setup_is_killed_and_reaped_at_deadline(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            script = parent / "candidate"
            script.write_text(
                f"#!{pathlib.Path(sys.executable).resolve()}\nraise SystemExit(0)\n",
                encoding="utf-8",
            )
            script.chmod(0o755)
            image = SHTEST.capture_executable(script, "candidate")
            notify_read, notify_write = os.pipe()
            release_read, release_write = os.pipe()
            observed_read, observed_write = os.pipe()
            controller = self.delayed_pipe_release(
                notify_read,
                notify_write,
                release_read,
                release_write,
                observed_read,
                observed_write,
                0.75,
            )
            original_mount = SHTEST.mount_linux
            original_close_child_descriptors = SHTEST.close_child_descriptors
            runner_pid = os.getpid()
            blocked = False

            def block_private_mount(
                source: bytes | None,
                target: pathlib.Path,
                filesystem: bytes | None,
                flags: int,
                data: bytes | None,
            ) -> None:
                nonlocal blocked
                if os.getpid() != runner_pid and target == pathlib.Path("/") and not blocked:
                    blocked = True
                    os.write(notify_write, str(os.getpid()).encode("ascii"))
                    os.read(release_read, 1)
                original_mount(source, target, filesystem, flags, data)

            def keep_blocker_descriptors(keep: set[int]) -> None:
                original_close_child_descriptors(keep | {notify_write, release_read})

            started = time.monotonic()
            try:
                with (
                    mock.patch.object(SHTEST, "PROCESS_SETUP_SECONDS", 0.05),
                    mock.patch.object(SHTEST, "mount_linux", side_effect=block_private_mount),
                    mock.patch.object(
                        SHTEST,
                        "close_child_descriptors",
                        side_effect=keep_blocker_descriptors,
                    ),
                    mock.patch.object(
                        SHTEST.subprocess, "Popen", wraps=subprocess.Popen
                    ) as popen,
                    self.assertRaises(SHTEST.ProcessSetupError) as raised,
                ):
                    SHTEST.run_process(image, [], b"", 1, parent)
                elapsed = time.monotonic() - started
                child_pid = int(os.read(observed_read, 64))
                self.assertTrue(raised.exception.timed_out)
                self.assertEqual(raised.exception.report_stage, "process_setup_timeout")
                self.assertEqual(raised.exception.role, "candidate")
                self.assertEqual(raised.exception.step, "child_setup")
                self.assertIsNotNone(raised.exception.result)
                assert raised.exception.result is not None
                self.assertFalse(raised.exception.result.cleanup_incomplete)
                self.assertLessEqual(
                    len(base64.b64decode(raised.exception.result.stdout_b64)),
                    SHTEST.MAX_CAPTURE_BYTES,
                )
                self.assertLessEqual(
                    len(base64.b64decode(raised.exception.result.stderr_b64)),
                    SHTEST.MAX_CAPTURE_BYTES,
                )
                self.assertLess(elapsed, 0.5)
                popen.assert_not_called()
                self.assertFalse(pathlib.Path(f"/proc/{child_pid}").exists())
                self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])
            finally:
                for descriptor in (notify_write, release_read, observed_read):
                    os.close(descriptor)
                os.waitpid(controller, 0)
                image.close()

    def test_parent_delay_after_exec_uses_case_timeout_and_bounded_cleanup(self) -> None:
        image = SHTEST.capture_executable(
            pathlib.Path(sys.executable).resolve(), "candidate"
        )
        real_await = SHTEST.await_child_setup
        real_terminate = SHTEST.terminate_process_tree
        retained_workspace: pathlib.Path | None = None

        def slow_await(*args: object, **kwargs: object) -> object:
            result = real_await(*args, **kwargs)
            time.sleep(0.10)
            return result

        def incomplete_process_cleanup(*args: object, **kwargs: object) -> object:
            real_terminate(*args, **kwargs)
            return SHTEST.ProcessTreeCleanupResult(False, True)

        def incomplete_workspace_cleanup(authority: object, budget: object) -> object:
            nonlocal retained_workspace
            retained_workspace = authority.path
            return SHTEST.WorkspaceCleanupResult(False, str(authority.path))

        try:
            with tempfile.TemporaryDirectory() as temporary:
                parent = pathlib.Path(temporary)
                with (
                    mock.patch.object(SHTEST, "PROCESS_SETUP_SECONDS", 0.05),
                    mock.patch.object(SHTEST, "await_child_setup", side_effect=slow_await),
                    mock.patch.object(
                        SHTEST,
                        "terminate_process_tree",
                        side_effect=incomplete_process_cleanup,
                    ),
                    mock.patch.object(
                        SHTEST,
                        "cleanup_retained_workspace",
                        side_effect=incomplete_workspace_cleanup,
                    ),
                ):
                    result = SHTEST.run_process(
                        image,
                        [
                            "-c",
                            "import sys,time; "
                            "sys.stdout.write('setup-partial\\n'); sys.stdout.flush(); "
                            "time.sleep(60)",
                        ],
                        b"",
                        0.05,
                        parent,
                    )
                self.assertTrue(result.cleanup_incomplete)
                self.assertTrue(result.timed_out)
                self.assertTrue(result.descendant_cleanup_required)
                self.assertEqual(result.quarantined_path, str(retained_workspace))
                self.assertEqual(base64.b64decode(result.stdout_b64), b"setup-partial\n")
                self.assertTrue(pathlib.Path(result.quarantined_path).exists())
                pathlib.Path(result.quarantined_path).rmdir()
        finally:
            image.close()

    def test_tracked_fork_setup_failure_is_structured_and_leak_free(self) -> None:
        image = SHTEST.capture_executable(
            pathlib.Path(sys.executable).resolve(), "candidate"
        )
        baseline_fds = len(os.listdir("/proc/self/fd"))
        try:
            with tempfile.TemporaryDirectory() as temporary:
                parent = pathlib.Path(temporary)
                with (
                    mock.patch.object(
                        SHTEST,
                        "fork_tracked_process",
                        side_effect=OSError("controlled tracked fork failure"),
                    ),
                    self.assertRaises(SHTEST.ProcessSetupError) as raised,
                ):
                    SHTEST.run_process(image, [], b"", 1, parent)
                self.assertFalse(raised.exception.timed_out)
                self.assertEqual(
                    raised.exception.report_stage, "process_setup_failure"
                )
                self.assertEqual(raised.exception.role, "candidate")
                self.assertEqual(raised.exception.step, "child_setup")
                self.assertEqual(list(parent.glob("shtest-quarantine-*")), [])
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
        finally:
            image.close()

    def test_setup_timeout_uses_existing_schema_v5_startup_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            report_path = directory / "report.json"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            images = [
                mock.Mock(
                    label=role,
                    sha256=role[0] * 64,
                    source_device=index,
                    source_inode=index + 10,
                )
                for index, role in enumerate(("oracle", "candidate"), 1)
            ]
            failure = SHTEST.ProcessSetupError(
                "oracle",
                "descendant_baseline",
                "controlled setup timeout",
                timed_out=True,
            )
            with (
                mock.patch.object(
                    SHTEST, "capture_executable", side_effect=images
                ),
                mock.patch.object(SHTEST, "version_of", side_effect=failure),
            ):
                status = SHTEST.main(
                    [
                        "--catalog",
                        str(catalog),
                        "--oracle",
                        str(directory / "oracle"),
                        "--candidate",
                        str(directory / "candidate"),
                        "--json-report",
                        str(report_path),
                    ]
                )
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual(status, 2)
            self.assertEqual(report["schema_version"], 5)
            self.assertEqual(
                report["startup_failure"],
                {
                    "stage": "process_setup_timeout",
                    "role": "oracle",
                    "message": "controlled setup timeout",
                    "process_result": None,
                },
            )

    def test_post_launch_setup_failure_report_preserves_process_result(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            report_path = directory / "report.json"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            images = [
                mock.Mock(
                    label=role,
                    sha256=role[0] * 64,
                    source_device=index,
                    source_inode=index + 10,
                )
                for index, role in enumerate(("oracle", "candidate"), 1)
            ]
            process_result = SHTEST.ProcessResult(
                argv=["oracle", "--version"],
                working_directory="/tmp/shtest-quarantine-retained",
                exit_status=None,
                signal=signal.SIGKILL,
                timed_out=False,
                duration_ms=80,
                stdout_b64=b64(b"partial-version"),
                stderr_b64=b64(b""),
                stdout_truncated=False,
                stderr_truncated=False,
                output_limit_exceeded=False,
                pipe_drain_timed_out=False,
                descendant_cleanup_required=True,
                cleanup_incomplete=True,
                quarantined_path="/tmp/shtest-quarantine-retained",
            )
            failure = SHTEST.ProcessSetupError(
                "oracle",
                "popen",
                "controlled post-launch setup timeout",
                timed_out=True,
                result=process_result,
            )
            with (
                mock.patch.object(
                    SHTEST, "capture_executable", side_effect=images
                ),
                mock.patch.object(SHTEST, "version_of", side_effect=failure),
                mock.patch("builtins.print"),
            ):
                status = SHTEST.main(
                    [
                        "--catalog",
                        str(catalog),
                        "--oracle",
                        str(directory / "oracle"),
                        "--candidate",
                        str(directory / "candidate"),
                        "--json-report",
                        str(report_path),
                    ]
                )
            report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertEqual(status, 2)
        self.assertEqual(report["schema_version"], 5)
        self.assertEqual(report["startup_failure"]["stage"], "process_setup_timeout")
        self.assertEqual(report["startup_failure"]["role"], "oracle")
        self.assertEqual(
            report["startup_failure"]["process_result"],
            SHTEST.asdict(process_result),
        )

    def test_exit_observed_after_deadline_is_timed_out_symmetrically(self) -> None:
        original_selector = SHTEST.selectors.DefaultSelector

        class OversleepSelector:
            def __init__(self) -> None:
                self.inner = original_selector()
                self.delayed = False

            def __getattr__(self, name: str) -> object:
                return getattr(self.inner, name)

            def select(self, timeout: float | None = None) -> list[object]:
                if not self.delayed:
                    self.delayed = True
                    time.sleep(0.15)
                    return []
                return self.inner.select(timeout)

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            helper = directory / "deadline_exit.py"
            marker = directory / "leader.pid"
            helper.write_text(
                "import os,pathlib,time\n"
                f"pathlib.Path({str(marker)!r}).write_text(str(os.getpid()))\n"
                "import sys\n"
                "sys.stdout.write('partial-before-deadline\\n'); sys.stdout.flush()\n"
                "time.sleep(0.07)\n",
                encoding="utf-8",
            )
            image = SHTEST.capture_executable(
                pathlib.Path(sys.executable).resolve(), "oracle"
            )
            try:
                baseline_fds = len(os.listdir("/proc/self/fd"))
                with mock.patch.object(
                    SHTEST.selectors, "DefaultSelector", OversleepSelector
                ):
                    for role in ("oracle", "candidate"):
                        image.label = role
                        result = SHTEST.run_process(image, [str(helper)], b"", 0.1)
                        leader_pid = int(marker.read_text(encoding="ascii"))
                        self.assertTrue(result.timed_out)
                        self.assertIsNone(result.exit_status)
                        self.assertIsNone(result.signal)
                        self.assertEqual(
                            base64.b64decode(result.stdout_b64),
                            b"partial-before-deadline\n",
                        )
                        self.assertFalse(result.cleanup_incomplete)
                        self.assertFalse(pathlib.Path(f"/proc/{leader_pid}").exists())
                        self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
            finally:
                image.close()

    def test_execution_deadline_is_inclusive(self) -> None:
        setup = SHTEST.ChildSetupOutcome(None, 123.0)
        assert setup.execution_started is not None
        deadline = SHTEST.execution_deadline_from_observation(
            setup.execution_started, 0.5
        )
        self.assertFalse(SHTEST.execution_deadline_reached(deadline - 0.000001, deadline))
        self.assertTrue(SHTEST.execution_deadline_reached(deadline, deadline))
        self.assertTrue(SHTEST.execution_deadline_reached(deadline + 0.000001, deadline))

    def test_cleanup_exhaustion_with_none_returncode_is_structured_and_leak_free(self) -> None:
        class UnresponsiveProcess:
            def __init__(self) -> None:
                stdin_read, stdin_write = os.pipe()
                stdout_read, stdout_write = os.pipe()
                stderr_read, stderr_write = os.pipe()
                os.close(stdin_read)
                os.close(stdout_write)
                os.close(stderr_write)
                self.stdin = os.fdopen(stdin_write, "wb", buffering=0)
                self.stdout = os.fdopen(stdout_read, "rb", buffering=0)
                self.stderr = os.fdopen(stderr_read, "rb", buffering=0)
                self.pid = 99999999
                self.returncode = None

            def poll(self) -> None:
                return None

            def wait(self, timeout: float | None = None) -> None:
                raise subprocess.TimeoutExpired(["unresponsive"], timeout)

        executable = mock.Mock(
            path=pathlib.Path("unresponsive"),
            fd=123,
            is_script=True,
            interpreter=None,
            elf_interpreter=None,
            origin_dependencies=(),
        )
        original_process_identity = SHTEST.process_identity

        def identity(pid: int) -> tuple[int, int] | None:
            if pid == 99999999:
                return (pid, 12345)
            return original_process_identity(pid)

        baseline_fds = len(os.listdir("/proc/self/fd"))

        def exhaust_cleanup_deadline(*args: object) -> object:
            budget = args[-1]
            assert isinstance(budget, SHTEST.TraversalBudget)
            budget.deadline = time.monotonic() - 1
            return SHTEST.ProcessTreeCleanupResult(False, False)

        for _ in range(10):
            process = UnresponsiveProcess()
            with (
                mock.patch.object(SHTEST, "enable_child_subreaper"),
                mock.patch.object(
                    SHTEST,
                    "create_execution_image",
                    side_effect=lambda *args: os.dup(0),
                ),
                mock.patch.object(
                    SHTEST,
                    "fork_tracked_process",
                    side_effect=lambda *args: (process, os.dup(0)),
                ),
                mock.patch.object(
                    SHTEST,
                    "await_child_setup",
                    side_effect=lambda *args: SHTEST.ChildSetupOutcome(
                        None, time.monotonic()
                    ),
                ),
                mock.patch.object(SHTEST, "process_identity", side_effect=identity),
                mock.patch.object(
                    SHTEST,
                    "terminate_process_tree",
                    side_effect=exhaust_cleanup_deadline,
                ),
                mock.patch.object(SHTEST, "signal_identity") as final_signal,
            ):
                result = SHTEST.run_process(executable, [], b"", 0.001)
            self.assertIsNone(result.exit_status)
            self.assertIsNone(result.signal)
            self.assertTrue(result.timed_out)
            self.assertTrue(result.cleanup_incomplete)
            self.assertFalse(result.descendant_cleanup_required)
            self.assertEqual(
                SHTEST.oracle_result_error(result),
                "oracle timed out",
            )
            final_signal.assert_called_once_with((99999999, 12345))
            self.assertTrue(process.stdin.closed)
            self.assertTrue(process.stdout.closed)
            self.assertTrue(process.stderr.closed)
            self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
            pathlib.Path(result.working_directory).rmdir()

    def test_normal_exit_reaps_new_session_escape_without_waiting_for_pipe_eof(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        marker = pathlib.Path(temporary.name) / "escape.pid"
        started = time.monotonic()
        completed, report, _ = self.run_harness(
            [run_case(timeout=2)],
            "escape-candidate",
            candidate_target=marker,
        )
        elapsed = time.monotonic() - started
        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertLess(elapsed, 1.5)
        result = report["cases"][0]["candidate"]
        self.assertEqual(base64.b64decode(result["stdout_b64"]), b"leader-exited")
        self.assertFalse(result["pipe_drain_timed_out"])
        self.assertFalse(result["cleanup_incomplete"])
        self.assertTrue(result["descendant_cleanup_required"])
        self.assertFalse(pathlib.Path(result["working_directory"]).exists())
        escaped_pid, escaped_pgid = map(int, marker.read_text(encoding="ascii").split())
        self.assertFalse(pathlib.Path(f"/proc/{escaped_pid}").exists())
        with self.assertRaises(ProcessLookupError):
            os.killpg(escaped_pgid, 0)

    def test_matching_candidate_detached_child_is_killed_and_case_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            marker = pathlib.Path(temporary) / "detached.pid"
            completed, report, _ = self.run_harness(
                [run_case()],
                "detached-matching-candidate",
                candidate_target=marker,
            )
            detached_pid = int(marker.read_text(encoding="ascii"))
        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        entry = report["cases"][0]
        self.assertEqual(entry["status"], "fail")
        self.assertEqual(
            entry["differences"],
            [
                "descendant cleanup requirement differs: "
                "oracle=False, candidate=True"
            ],
        )
        self.assertFalse(entry["oracle"]["descendant_cleanup_required"])
        self.assertTrue(entry["candidate"]["descendant_cleanup_required"])
        self.assertFalse(entry["candidate"]["cleanup_incomplete"])
        self.assertFalse(pathlib.Path(f"/proc/{detached_pid}").exists())

    def test_expanding_escaped_process_storm_is_bounded_and_leak_free(self) -> None:
        baseline_fds = len(os.listdir("/proc/self/fd"))
        for iteration in range(3):
            with self.subTest(iteration=iteration), tempfile.TemporaryDirectory() as temporary:
                marker = pathlib.Path(temporary) / "storm.identities"
                identities: set[tuple[int, int]] = set()
                try:
                    started = time.monotonic()
                    completed, report, _ = self.run_harness(
                        [run_case(timeout=2)],
                        "escape-storm",
                        candidate_target=marker,
                    )
                    elapsed = time.monotonic() - started
                    if marker.exists():
                        identities = {
                            tuple(map(int, line.split()))
                            for line in marker.read_text(
                                encoding="ascii"
                            ).splitlines()
                        }
                    self.assertEqual(
                        completed.returncode,
                        1,
                        completed.stdout + completed.stderr,
                    )
                    self.assertLess(elapsed, 2.5)
                    result = report["cases"][0]["candidate"]
                    self.assertEqual(
                        base64.b64decode(result["stdout_b64"]), b"storm-started"
                    )
                    self.assertFalse(result["cleanup_incomplete"])
                    self.assertGreaterEqual(len(identities), 8)
                    for pid, start_time in identities:
                        self.assertNotEqual(
                            SHTEST.process_identity(pid), (pid, start_time)
                        )
                    self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)
                finally:
                    for identity in identities:
                        if SHTEST.process_identity(identity[0]) == identity:
                            SHTEST.signal_identity(identity)
                    cleanup_deadline = time.monotonic() + 0.5
                    while time.monotonic() < cleanup_deadline and any(
                        SHTEST.process_identity(pid) == (pid, start_time)
                        for pid, start_time in identities
                    ):
                        time.sleep(0.01)

    def test_huge_process_table_stops_at_budget_and_returns_incomplete(self) -> None:
        class Entry:
            def __init__(self, name: str) -> None:
                self.name = name

        class HugeProc:
            def __init__(self, counter: list[int]) -> None:
                self.counter = counter

            def __enter__(self) -> "HugeProc":
                return self

            def __exit__(self, *args: object) -> None:
                return None

            def __iter__(self) -> "HugeProc":
                return self

            def __next__(self) -> Entry:
                self.counter[0] += 1
                return Entry(str(700000 + self.counter[0] - 1))

        class UnresponsiveProcess:
            def __init__(self) -> None:
                stdin_read, stdin_write = os.pipe()
                stdout_read, stdout_write = os.pipe()
                stderr_read, stderr_write = os.pipe()
                os.close(stdin_read)
                os.close(stdout_write)
                os.close(stderr_write)
                self.stdin = os.fdopen(stdin_write, "wb", buffering=0)
                self.stdout = os.fdopen(stdout_read, "rb", buffering=0)
                self.stderr = os.fdopen(stderr_read, "rb", buffering=0)
                self.pid = 700000
                self.returncode = None

            def poll(self) -> None:
                return None

            def wait(self, timeout: float | None = None) -> None:
                raise subprocess.TimeoutExpired(["huge-proc"], timeout)

        executable = mock.Mock(
            path=pathlib.Path("huge-proc"),
            fd=123,
            is_script=True,
            interpreter=None,
            elf_interpreter=None,
            origin_dependencies=(),
        )
        original_budget = SHTEST.TraversalBudget
        original_scandir = os.scandir
        parent_pid = os.getpid()
        signaled: list[int] = []
        pidfd_targets: dict[int, int] = {}

        def fake_pidfd_open(pid: int, flags: int = 0) -> int:
            descriptor = os.dup(0)
            pidfd_targets[descriptor] = pid
            return descriptor

        def record_pidfd_signal(
            descriptor: int, sent_signal: int, siginfo: object, flags: int = 0
        ) -> None:
            signaled.append(pidfd_targets[descriptor])

        def stat_for(pid: int) -> tuple[str, int, int] | None:
            if pid == 700000:
                return ("S", parent_pid, 1000)
            if pid in (700001, 700002):
                return ("S", 700000, pid - 699000)
            return ("S", 1, pid - 699000)

        def identity_for(pid: int) -> tuple[int, int] | None:
            if pid == 700002:
                return (pid, 9999)  # PID reuse after the snapshot.
            info = stat_for(pid)
            return None if info is None else (pid, info[2])

        baseline_fds = len(os.listdir("/proc/self/fd"))
        for iteration in range(10):
            with self.subTest(iteration=iteration):
                counter = [0]
                process = UnresponsiveProcess()
                started = time.monotonic()
                with (
                    mock.patch.object(SHTEST, "enable_child_subreaper"),
                    mock.patch.object(SHTEST, "descendant_baseline", return_value=set()),
                    mock.patch.object(
                        SHTEST,
                        "create_execution_image",
                        side_effect=lambda *args: os.dup(0),
                    ),
                    mock.patch.object(
                        SHTEST,
                        "fork_tracked_process",
                        side_effect=lambda *args: (process, os.dup(0)),
                    ),
                    mock.patch.object(
                        SHTEST,
                        "await_child_setup",
                        side_effect=lambda *args: SHTEST.ChildSetupOutcome(
                            None, time.monotonic()
                        ),
                    ),
                    mock.patch.object(
                        SHTEST.os,
                        "scandir",
                        side_effect=lambda path: (
                            HugeProc(counter)
                            if not isinstance(path, int) and os.fspath(path) == "/proc"
                            else original_scandir(path)
                        ),
                    ),
                    mock.patch.object(SHTEST, "process_stat", side_effect=stat_for),
                    mock.patch.object(
                        SHTEST, "process_identity", side_effect=identity_for
                    ),
                    mock.patch.object(
                        SHTEST,
                        "TraversalBudget",
                        side_effect=lambda deadline: original_budget(
                            deadline,
                            scan_entries=8,
                            identity_reads=8,
                            discoveries=8,
                        ),
                    ),
                    mock.patch.object(
                        SHTEST.os, "pidfd_open", side_effect=fake_pidfd_open
                    ),
                    mock.patch.object(
                        SHTEST.signal,
                        "pidfd_send_signal",
                        side_effect=record_pidfd_signal,
                    ),
                ):
                    result = SHTEST.run_process(executable, [], b"", 0.001)
                elapsed = time.monotonic() - started
                self.assertLess(elapsed, 0.25)
                self.assertLessEqual(counter[0], 16)
                self.assertTrue(result.timed_out)
                self.assertTrue(result.descendant_cleanup_required)
                self.assertTrue(result.cleanup_incomplete)
                self.assertTrue(process.stdin.closed)
                self.assertTrue(process.stdout.closed)
                self.assertTrue(process.stderr.closed)
                self.assertIn(700000, signaled)
                self.assertIn(700001, signaled)
                self.assertNotIn(700002, signaled)
                self.assertEqual(len(os.listdir("/proc/self/fd")), baseline_fds)

    def test_process_snapshot_stops_at_shared_deadline(self) -> None:
        class Entry:
            name = "700000"

        class SlowProc:
            def __init__(self, counter: list[int]) -> None:
                self.counter = counter

            def __enter__(self) -> "SlowProc":
                return self

            def __exit__(self, *args: object) -> None:
                return None

            def __iter__(self) -> "SlowProc":
                return self

            def __next__(self) -> Entry:
                self.counter[0] += 1
                time.sleep(0.01)
                return Entry()

        for iteration in range(10):
            with self.subTest(iteration=iteration):
                counter = [0]
                deadline = time.monotonic() + 0.025
                budget = SHTEST.TraversalBudget(
                    deadline,
                    scan_entries=100000,
                    identity_reads=100000,
                    discoveries=100000,
                )
                started = time.monotonic()
                with (
                    mock.patch.object(
                        SHTEST.os,
                        "scandir",
                        return_value=SlowProc(counter),
                    ),
                    mock.patch.object(
                        SHTEST,
                        "process_stat",
                        return_value=("S", 1, 1000),
                    ),
                ):
                    snapshot = SHTEST.process_snapshot(budget)
                self.assertLess(time.monotonic() - started, 0.1)
                self.assertLessEqual(counter[0], 3)
                self.assertFalse(snapshot.complete)

    def test_workspace_cleanup_is_bounded_repeatable_and_does_not_escape(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            outside = parent / "outside"
            outside.mkdir()
            sentinel = outside / "sentinel"
            sentinel.write_bytes(b"keep")

            for iteration in range(5):
                workspace = parent / f"shtest-quarantine-hostile-{iteration}"
                workspace.mkdir()
                (workspace / "link-outside").symlink_to(outside, target_is_directory=True)
                (workspace / "locked").mkdir(mode=0o000)
                (workspace / "locked" / "payload").write_bytes(b"payload")
                os.chmod(workspace / "locked", 0o000)
                os.mkfifo(workspace / "fifo")
                special_socket = socket.socket(socket.AF_UNIX)
                special_socket.bind(str(workspace / "socket"))
                special_socket.close()
                for index in range(32):
                    (workspace / f"entry-{index}").write_bytes(b"x" * 16)

                budget = SHTEST.TraversalBudget(
                    time.monotonic() + 0.25,
                    workspace_entries=256,
                    workspace_bytes=1024 * 1024,
                    workspace_work=1024,
                )
                self.assertTrue(
                    SHTEST.cleanup_quarantined_workspace(workspace, budget)
                )
                self.assertFalse(workspace.exists())
                self.assertEqual(sentinel.read_bytes(), b"keep")

            for iteration in range(5):
                workspace = parent / f"shtest-quarantine-huge-{iteration}"
                workspace.mkdir()
                (workspace / "link-outside").symlink_to(outside, target_is_directory=True)
                for index in range(64):
                    (workspace / f"entry-{index}").write_bytes(b"x" * 32)
                started = time.monotonic()
                budget = SHTEST.TraversalBudget(
                    time.monotonic() + 0.05,
                    workspace_entries=4,
                    workspace_bytes=128,
                    workspace_work=16,
                )
                self.assertFalse(
                    SHTEST.cleanup_quarantined_workspace(workspace, budget)
                )
                self.assertLess(time.monotonic() - started, 0.15)
                retained = [
                    entry
                    for entry in parent.iterdir()
                    if entry.name.startswith(".shtest-recovery-")
                ]
                self.assertEqual(len(retained), 1)
                self.assertEqual(sentinel.read_bytes(), b"keep")
                # Test teardown is trusted and outside the adapter guarantee.
                for child in retained[0].iterdir():
                    child.unlink()
                retained[0].rmdir()

    def test_workspace_cleanup_permission_failure_is_structured(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = pathlib.Path(temporary) / "shtest-quarantine-permission"
            workspace.mkdir()
            blocked = workspace / "blocked"
            blocked.write_bytes(b"data")
            original_unlink = os.unlink

            def deny_blocked(path: object, *args: object, **kwargs: object) -> None:
                if os.fspath(path) == "blocked":
                    raise PermissionError("deterministic denial")
                original_unlink(path, *args, **kwargs)

            budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
            with mock.patch.object(SHTEST.os, "unlink", side_effect=deny_blocked):
                self.assertFalse(
                    SHTEST.cleanup_quarantined_workspace(workspace, budget)
                )
            retained = list(pathlib.Path(temporary).rglob("blocked"))
            self.assertEqual(len(retained), 1)
            self.assertEqual(retained[0].read_bytes(), b"data")

    def test_workspace_cleanup_refuses_a_different_mount_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = pathlib.Path(temporary) / "shtest-quarantine-mount"
            mounted = workspace / "mounted"
            mounted.mkdir(parents=True)
            sentinel = mounted / "sentinel"
            sentinel.write_bytes(b"keep")
            budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
            with mock.patch.object(
                SHTEST, "fd_mount_id", side_effect=[100, 200]
            ):
                self.assertFalse(
                    SHTEST.cleanup_quarantined_workspace(workspace, budget)
                )
            self.assertEqual(sentinel.read_bytes(), b"keep")
            self.assertTrue(workspace.exists())

    def test_workspace_cleanup_refuses_replaced_quarantine_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            workspace = pathlib.Path(temporary) / "shtest-quarantine-replaced"
            workspace.mkdir()
            expected = SHTEST.capture_workspace_identity(workspace)
            workspace.rmdir()
            workspace.mkdir()
            sentinel = workspace / "unrelated"
            sentinel.write_bytes(b"keep")
            budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
            self.assertFalse(
                SHTEST.cleanup_quarantined_workspace(
                    workspace, budget, expected
                )
            )
            self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_nested_directory_removal_stops_on_boundary_inode_substitution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            workspace = parent / "workspace"
            workspace.mkdir()
            child = workspace / "child"
            child.mkdir()
            unrelated = parent / "unrelated"
            unrelated.mkdir()
            sentinel = unrelated / "sentinel"
            sentinel.write_bytes(b"keep")
            authority = SHTEST.capture_workspace_authority(workspace)
            original_rename = SHTEST.rename_noreplace
            substituted = False

            def substitute_before_identity_bound_rename(
                old_parent_fd: int,
                old_name: str,
                new_parent_fd: int,
                new_name: str,
            ) -> None:
                nonlocal substituted
                if old_name == "child" and not substituted:
                    os.rename(
                        "child",
                        "candidate-moved",
                        src_dir_fd=old_parent_fd,
                        dst_dir_fd=old_parent_fd,
                    )
                    os.rename(
                        unrelated,
                        "child",
                        dst_dir_fd=old_parent_fd,
                    )
                    substituted = True
                original_rename(
                    old_parent_fd, old_name, new_parent_fd, new_name
                )

            try:
                with mock.patch.object(
                    SHTEST,
                    "rename_noreplace",
                    side_effect=substitute_before_identity_bound_rename,
                ):
                    result = SHTEST.cleanup_retained_workspace(
                        authority,
                        SHTEST.TraversalBudget(time.monotonic() + 0.5),
                    )
            finally:
                authority.close()

            self.assertTrue(substituted)
            self.assertFalse(result.complete)
            retained_sentinels = list(parent.rglob("sentinel"))
            self.assertEqual(len(retained_sentinels), 1)
            self.assertEqual(retained_sentinels[0].read_bytes(), b"keep")

    def test_recovery_removal_stops_on_boundary_inode_substitution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            workspace = parent / "workspace"
            workspace.mkdir()
            unrelated = parent / "unrelated"
            unrelated.mkdir()
            sentinel = unrelated / "sentinel"
            sentinel.write_bytes(b"keep")
            authority = SHTEST.capture_workspace_authority(workspace)
            original_rename = SHTEST.rename_noreplace
            recovery_renames = 0

            def substitute_recovery_before_final_rename(
                old_parent_fd: int,
                old_name: str,
                new_parent_fd: int,
                new_name: str,
            ) -> None:
                nonlocal recovery_renames
                if old_name.startswith(".shtest-recovery-"):
                    recovery_renames += 1
                    if recovery_renames == 1:
                        os.rename(
                            old_name,
                            "candidate-moved",
                            src_dir_fd=old_parent_fd,
                            dst_dir_fd=old_parent_fd,
                        )
                        os.rename(
                            unrelated,
                            old_name,
                            dst_dir_fd=old_parent_fd,
                        )
                original_rename(
                    old_parent_fd, old_name, new_parent_fd, new_name
                )

            try:
                with mock.patch.object(
                    SHTEST,
                    "rename_noreplace",
                    side_effect=substitute_recovery_before_final_rename,
                ):
                    result = SHTEST.cleanup_retained_workspace(
                        authority,
                        SHTEST.TraversalBudget(time.monotonic() + 0.5),
                    )
            finally:
                authority.close()

            self.assertEqual(recovery_renames, 1)
            self.assertFalse(result.complete)
            retained_sentinels = list(parent.rglob("sentinel"))
            self.assertEqual(len(retained_sentinels), 1)
            self.assertEqual(retained_sentinels[0].read_bytes(), b"keep")

    def test_workspace_churn_stops_at_cumulative_budget_and_deadline(self) -> None:
        class Entry:
            name = "continually-recreated"

        class ChurningDirectory:
            def __init__(self, counter: list[int]) -> None:
                self.counter = counter

            def __iter__(self) -> "ChurningDirectory":
                return self

            def __next__(self) -> Entry:
                self.counter[0] += 1
                return Entry()

            def close(self) -> None:
                return None

        with tempfile.TemporaryDirectory() as temporary:
            original_scandir = os.scandir
            original_stat = os.stat
            original_unlink = os.unlink
            for iteration in range(10):
                workspace = (
                    pathlib.Path(temporary)
                    / f"shtest-quarantine-churning-{iteration}"
                )
                workspace.mkdir()
                counter = [0]
                churn = ChurningDirectory(counter)

                def scan(path: object) -> object:
                    return churn if isinstance(path, int) else original_scandir(path)

                def stat_entry(path: object, *args: object, **kwargs: object) -> os.stat_result:
                    if os.fspath(path) == "continually-recreated":
                        return original_stat(workspace)
                    return original_stat(path, *args, **kwargs)

                def unlink_entry(path: object, *args: object, **kwargs: object) -> None:
                    if os.fspath(path) != "continually-recreated":
                        original_unlink(path, *args, **kwargs)

                budget = SHTEST.TraversalBudget(
                    time.monotonic() + 0.05,
                    workspace_entries=8,
                    workspace_bytes=1024 * 1024,
                    workspace_work=32,
                )
                started = time.monotonic()
                with (
                    mock.patch.object(SHTEST.os, "scandir", side_effect=scan),
                    mock.patch.object(SHTEST.os, "stat", side_effect=stat_entry),
                    mock.patch.object(SHTEST.os, "unlink", side_effect=unlink_entry),
                ):
                    self.assertFalse(
                        SHTEST.cleanup_quarantined_workspace(workspace, budget)
                    )
                self.assertLess(time.monotonic() - started, 0.15)
                self.assertLessEqual(counter[0], 16)
                retained = [
                    entry
                    for entry in pathlib.Path(temporary).iterdir()
                    if entry.name.startswith(".shtest-recovery-")
                ]
                self.assertEqual(len(retained), 1)
                retained[0].rmdir()

    def test_run_process_never_uses_implicit_temporary_directory_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            image = SHTEST.capture_executable(
                pathlib.Path(sys.executable).resolve(), "no-destructor-test"
            )
            try:
                with mock.patch.object(
                    SHTEST.tempfile,
                    "TemporaryDirectory",
                    side_effect=AssertionError("implicit cleanup used"),
                ):
                    result = SHTEST.run_process(
                        image,
                        ["-c", "print('ok')"],
                        b"",
                        2,
                        pathlib.Path(temporary),
                    )
            finally:
                image.close()
        self.assertEqual(result.exit_status, 0)
        self.assertFalse(result.cleanup_incomplete)
        self.assertIsNone(result.quarantined_path)
        self.assertFalse(pathlib.Path(result.working_directory).exists())

    def test_run_process_removes_workspace_renamed_within_trusted_parent(self) -> None:
        code = """
import os
import pathlib
cwd = pathlib.Path.cwd()
moved = cwd.with_name(cwd.name + "-moved")
os.rename(cwd, moved)
(moved / "survivor").write_bytes(b"must-not-survive")
"""
        for iteration in range(5):
            with self.subTest(iteration=iteration), tempfile.TemporaryDirectory() as temporary:
                parent = pathlib.Path(temporary)
                result = self.run_python_candidate(parent, code)
                self.assertFalse(result.cleanup_incomplete)
                self.assertIsNone(result.quarantined_path)
                self.assertEqual(list(parent.iterdir()), [])

    def test_run_process_accepts_child_removed_empty_workspace(self) -> None:
        code = """
import os
import pathlib
workspace = pathlib.Path.cwd()
os.chdir(workspace.parent)
os.rmdir(workspace)
"""
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            result = self.run_python_candidate(parent, code)

        self.assertEqual(result.exit_status, 0)
        self.assertFalse(result.cleanup_incomplete)
        self.assertIsNone(result.quarantined_path)

    def test_run_process_fails_closed_on_rename_exchange_replacement(self) -> None:
        code = """
import ctypes
import os
import pathlib
cwd = pathlib.Path.cwd()
replacement = cwd.with_name(cwd.name + "-exchange")
replacement.mkdir()
(replacement / "replacement").write_bytes(b"keep")
libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
renameat2.restype = ctypes.c_int
if renameat2(-100, os.fsencode(cwd), -100, os.fsencode(replacement), 2) != 0:
    raise OSError(ctypes.get_errno(), "renameat2 exchange")
(pathlib.Path.cwd() / "survivor").write_bytes(b"must-not-survive")
"""
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            result = self.run_python_candidate(parent, code)
            if result.exit_status != 0 and b"renameat2" in base64.b64decode(result.stderr_b64):
                self.skipTest("renameat2 exchange is unavailable")
            self.assertEqual(result.exit_status, 0)
            self.assertTrue(result.cleanup_incomplete)
            self.assertEqual(result.quarantined_path, result.working_directory)
            self.assertFalse(any(parent.rglob("survivor")))
            replacement = pathlib.Path(result.working_directory) / "replacement"
            self.assertEqual(replacement.read_bytes(), b"keep")

    def test_run_process_fails_closed_on_original_path_replacement(self) -> None:
        code = """
import os
import pathlib
cwd = pathlib.Path.cwd()
moved = cwd.with_name(cwd.name + "-moved")
os.rename(cwd, moved)
cwd.mkdir()
(cwd / "replacement").write_bytes(b"keep")
(moved / "survivor").write_bytes(b"must-not-survive")
"""
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            result = self.run_python_candidate(parent, code)
            self.assertTrue(result.cleanup_incomplete)
            self.assertEqual(result.quarantined_path, result.working_directory)
            self.assertFalse(any(parent.rglob("survivor")))
            self.assertEqual(
                (pathlib.Path(result.quarantined_path) / "replacement").read_bytes(),
                b"keep",
            )

    def test_run_process_does_not_follow_original_path_symlink_substitution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            parent = root / "boundary"
            parent.mkdir()
            outside = root / "outside"
            outside.mkdir()
            sentinel = outside / "sentinel"
            sentinel.write_bytes(b"keep")
            code = f"""
import os
import pathlib
cwd = pathlib.Path.cwd()
moved = cwd.with_name(cwd.name + "-moved")
os.rename(cwd, moved)
cwd.symlink_to({str(outside)!r}, target_is_directory=True)
(moved / "survivor").write_bytes(b"must-not-survive")
"""
            result = self.run_python_candidate(parent, code)
            self.assertTrue(result.cleanup_incomplete)
            self.assertEqual(result.quarantined_path, result.working_directory)
            self.assertTrue(pathlib.Path(result.quarantined_path).is_symlink())
            self.assertEqual(sentinel.read_bytes(), b"keep")
            self.assertFalse(any(parent.rglob("survivor")))

    def test_run_process_cleans_workspace_after_trusted_parent_rename(self) -> None:
        code = """
import os
import pathlib
cwd = pathlib.Path.cwd()
parent = cwd.parent
os.rename(parent, parent.with_name(parent.name + "-moved"))
(pathlib.Path.cwd() / "survivor").write_bytes(b"must-not-survive")
"""
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            parent = root / "boundary"
            parent.mkdir()
            result = self.run_python_candidate(parent, code)
            self.assertFalse(result.cleanup_incomplete)
            self.assertIsNone(result.quarantined_path)
            self.assertFalse(parent.exists())
            self.assertEqual(list((root / "boundary-moved").iterdir()), [])

    def test_run_process_reports_identity_when_workspace_escapes_search_boundary(self) -> None:
        code = """
import os
import pathlib
cwd = pathlib.Path.cwd()
escaped = cwd.parent.parent / "escaped-quarantine"
os.rename(cwd, escaped)
(escaped / "survivor").write_bytes(b"must-not-survive")
"""
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            parent = root / "boundary"
            parent.mkdir()
            started = time.monotonic()
            result = self.run_python_candidate(parent, code)
            self.assertLess(time.monotonic() - started, 3.0)
            self.assertTrue(result.cleanup_incomplete)
            assert result.quarantined_path is not None
            self.assertIn(str(parent), result.quarantined_path)
            self.assertRegex(
                result.quarantined_path,
                r"device=\d+ inode=\d+ mount=\d+",
            )
            escaped = root / "escaped-quarantine"
            self.assertTrue(escaped.is_dir())
            self.assertFalse((escaped / "survivor").exists())

    def test_retained_workspace_cleanup_never_false_cleans_during_exchange_churn(self) -> None:
        libc = ctypes.CDLL(None, use_errno=True)
        renameat2 = getattr(libc, "renameat2", None)
        if renameat2 is None:
            self.skipTest("renameat2 exchange is unavailable")
        renameat2.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameat2.restype = ctypes.c_int

        for iteration in range(20):
            with self.subTest(iteration=iteration), tempfile.TemporaryDirectory() as temporary:
                parent = pathlib.Path(temporary)
                workspace = parent / "workspace"
                replacement = parent / "replacement"
                workspace.mkdir()
                replacement.mkdir()
                (workspace / "sentinel").write_bytes(b"candidate")
                (replacement / "unrelated").write_bytes(b"keep")
                authority = SHTEST.capture_workspace_authority(workspace)
                stop = threading.Event()

                def churn() -> None:
                    while not stop.is_set():
                        renameat2(
                            -100,
                            os.fsencode(workspace),
                            -100,
                            os.fsencode(replacement),
                            2,
                        )

                thread = threading.Thread(target=churn)
                thread.start()
                started = time.monotonic()
                try:
                    budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
                    result = SHTEST.cleanup_retained_workspace(authority, budget)
                    retained_links = os.fstat(authority.root_fd).st_nlink
                finally:
                    stop.set()
                    thread.join(timeout=1)
                    authority.close()
                self.assertFalse(thread.is_alive())
                self.assertLess(time.monotonic() - started, 0.5)
                unrelated = list(parent.rglob("unrelated"))
                self.assertEqual(len(unrelated), 1)
                self.assertEqual(unrelated[0].read_bytes(), b"keep")
                if result.complete:
                    self.assertEqual(retained_links, 0)
                    self.assertFalse(any(parent.rglob("sentinel")))
                else:
                    self.assertIsNotNone(result.quarantined_path)

    def test_workspace_cleanup_failure_preserves_main_process_result(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = pathlib.Path(temporary)
            image = SHTEST.capture_executable(
                pathlib.Path(sys.executable).resolve(), "quarantine-result-test"
            )
            quarantined: list[pathlib.Path] = []

            def fail_cleanup(
                authority: object, budget: object
            ) -> object:
                quarantined.append(authority.path)
                return SHTEST.WorkspaceCleanupResult(False, str(authority.path))

            try:
                with mock.patch.object(
                    SHTEST,
                    "cleanup_retained_workspace",
                    side_effect=fail_cleanup,
                ):
                    result = SHTEST.run_process(
                        image,
                        ["-c", "print('main-outcome')"],
                        b"",
                        2,
                        parent,
                    )
            finally:
                image.close()
            self.assertEqual(result.exit_status, 0)
            self.assertEqual(base64.b64decode(result.stdout_b64), b"main-outcome\n")
            self.assertTrue(result.cleanup_incomplete)
            self.assertEqual(result.quarantined_path, result.working_directory)
            self.assertEqual(quarantined, [pathlib.Path(result.working_directory)])
            self.assertTrue(pathlib.Path(result.quarantined_path).exists())
            pathlib.Path(result.quarantined_path).rmdir()

    def test_pidfd_signal_rejects_reuse_before_validation(self) -> None:
        identity = (700000, 1000)
        reused = (700000, 2000)
        with (
            mock.patch.object(SHTEST.os, "pidfd_open", return_value=91) as pidfd_open,
            mock.patch.object(SHTEST, "process_identity", return_value=reused),
            mock.patch.object(SHTEST.signal, "pidfd_send_signal") as pidfd_signal,
            mock.patch.object(SHTEST.os, "close") as close,
            mock.patch.object(SHTEST.os, "kill") as numeric_kill,
        ):
            self.assertFalse(SHTEST.signal_identity(identity))
        pidfd_open.assert_called_once_with(700000, 0)
        pidfd_signal.assert_not_called()
        numeric_kill.assert_not_called()
        close.assert_called_once_with(91)

    def test_pidfd_signal_stays_bound_across_post_validation_reuse(self) -> None:
        identity = (700000, 1000)
        reused = (700000, 2000)
        observed_after_validation: list[tuple[int, int] | None] = []

        def send_bound(*args: object) -> None:
            observed_after_validation.append(SHTEST.process_identity(700000))

        with (
            mock.patch.object(SHTEST.os, "pidfd_open", return_value=92),
            mock.patch.object(
                SHTEST, "process_identity", side_effect=[identity, reused]
            ),
            mock.patch.object(
                SHTEST.signal, "pidfd_send_signal", side_effect=send_bound
            ) as pidfd_signal,
            mock.patch.object(SHTEST.os, "close") as close,
            mock.patch.object(SHTEST.os, "kill") as numeric_kill,
        ):
            self.assertTrue(SHTEST.signal_identity(identity))
        self.assertEqual(observed_after_validation, [reused])
        pidfd_signal.assert_called_once_with(92, signal.SIGKILL, None, 0)
        numeric_kill.assert_not_called()
        close.assert_called_once_with(92)

    def test_process_group_cleanup_uses_identity_bound_leader_signal(self) -> None:
        identity = SHTEST.ProcessGroupIdentity(700000, 1000, 700000, 700000)
        with (
            mock.patch.object(SHTEST, "signal_identity", return_value=True) as bound,
            mock.patch.object(SHTEST.os, "killpg") as numeric_group_signal,
        ):
            self.assertTrue(SHTEST.signal_process_group(identity))
        bound.assert_called_once_with((700000, 1000))
        numeric_group_signal.assert_not_called()

    def test_real_process_group_identity_is_validated_before_signal(self) -> None:
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            start_new_session=True,
        )
        identity = SHTEST.process_group_identity(process.pid)
        self.assertIsNotNone(identity)
        assert identity is not None
        self.assertTrue(SHTEST.signal_process_group(identity))
        process.wait(timeout=2)
        with mock.patch.object(SHTEST.signal, "pidfd_send_signal") as pidfd_signal:
            self.assertFalse(SHTEST.signal_process_group(identity))
            pidfd_signal.assert_not_called()

    def test_failed_group_signal_falls_back_to_real_leader_identity(self) -> None:
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            start_new_session=True,
        )
        leader_group = SHTEST.process_group_identity(process.pid)
        self.assertIsNotNone(leader_group)
        assert leader_group is not None
        try:
            budget = SHTEST.TraversalBudget(time.monotonic() + 0.05)
            with mock.patch.object(
                SHTEST, "signal_process_group", return_value=False
            ):
                cleanup_result = SHTEST.terminate_process_tree(
                    process,
                    set(),
                    SHTEST.process_identity(process.pid),
                    leader_group,
                    budget,
                )
            process.wait(timeout=1)
            self.assertTrue(cleanup_result.complete)
            self.assertFalse(cleanup_result.descendant_cleanup_required)
        finally:
            if process.poll() is None:
                os.kill(process.pid, signal.SIGKILL)
                process.wait(timeout=1)

    def test_leader_fallback_rejects_reused_identity(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        budget = SHTEST.TraversalBudget(time.monotonic() - 1)
        with (
            mock.patch.object(
                SHTEST,
                "process_identity",
                return_value=(700000, 2000),
            ),
            mock.patch.object(SHTEST.os, "kill") as kill,
        ):
            cleanup_result = SHTEST.terminate_process_tree(
                process, set(), (700000, 1000), None, budget
            )
            self.assertFalse(cleanup_result.complete)
            self.assertFalse(cleanup_result.descendant_cleanup_required)
        kill.assert_not_called()

    def test_normal_exit_cleanup_never_adopts_reused_leader_identity(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        reused = (700000, 2000)
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
        with (
            mock.patch.object(SHTEST, "process_identity", return_value=reused),
            mock.patch.object(SHTEST, "process_snapshot") as snapshot,
            mock.patch.object(SHTEST, "signal_process_group", return_value=False),
            mock.patch.object(SHTEST.os, "kill") as kill,
        ):
            snapshot.return_value = SHTEST.ProcessSnapshot({}, {}, True)
            cleanup_result = SHTEST.terminate_process_tree(
                process, set(), (700000, 1000), None, budget
            )
            self.assertTrue(cleanup_result.complete)
            self.assertFalse(cleanup_result.descendant_cleanup_required)
        kill.assert_not_called()

    def test_failed_group_validation_never_adopts_reused_leader_identity(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        leader_group = SHTEST.ProcessGroupIdentity(
            700000, 1000, 700000, 700000
        )
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
        with (
            mock.patch.object(
                SHTEST, "process_identity", return_value=(700000, 2000)
            ),
            mock.patch.object(SHTEST, "process_snapshot") as snapshot,
            mock.patch.object(
                SHTEST, "signal_process_group", return_value=False
            ) as group_signal,
            mock.patch.object(SHTEST.os, "kill") as kill,
        ):
            snapshot.return_value = SHTEST.ProcessSnapshot({}, {}, True)
            cleanup_result = SHTEST.terminate_process_tree(
                process,
                set(),
                (700000, 1000),
                leader_group,
                budget,
            )
            self.assertTrue(cleanup_result.complete)
            self.assertFalse(cleanup_result.descendant_cleanup_required)
        group_signal.assert_called_once_with(leader_group)
        kill.assert_not_called()

    def test_direct_reused_leader_pid_remains_live_and_cleanup_incomplete(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        leader_identity = (700000, 1000)
        reused_identity = (700000, 2000)
        baseline_identity = (700000, 500)
        leader_group = SHTEST.ProcessGroupIdentity(
            700000, 1000, 700000, 700000
        )
        snapshot = SHTEST.ProcessSnapshot(
            {os.getpid(): {700000}}, {700000: reused_identity}, True
        )
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.03)
        with (
            mock.patch.object(SHTEST, "process_snapshot", return_value=snapshot),
            mock.patch.object(SHTEST, "signal_process_group", return_value=True),
            mock.patch.object(SHTEST, "signal_identity", return_value=True) as signal_identity,
            mock.patch.object(SHTEST, "reap_identities", return_value=True),
            mock.patch.object(
                SHTEST,
                "identity_is_running",
                side_effect=lambda identity: identity == reused_identity,
            ),
        ):
            cleanup_result = SHTEST.terminate_process_tree(
                process,
                {baseline_identity},
                leader_identity,
                leader_group,
                budget,
            )
        self.assertFalse(cleanup_result.complete)
        self.assertTrue(cleanup_result.descendant_cleanup_required)
        self.assertIn(mock.call(reused_identity), signal_identity.call_args_list)

    def test_root_reused_leader_pid_remains_live_and_cleanup_incomplete(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = None
        leader_identity = (700000, 1000)
        reused_identity = (700000, 2000)
        leader_group = SHTEST.ProcessGroupIdentity(
            700000, 1000, 700000, 700000
        )
        snapshot = SHTEST.ProcessSnapshot({}, {700000: reused_identity}, True)
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.03)
        with (
            mock.patch.object(SHTEST, "process_snapshot", return_value=snapshot),
            mock.patch.object(SHTEST, "signal_process_group", return_value=True),
            mock.patch.object(SHTEST, "signal_identity", return_value=True) as signal_identity,
            mock.patch.object(SHTEST, "reap_identities", return_value=True),
            mock.patch.object(
                SHTEST,
                "identity_is_running",
                side_effect=lambda identity: identity == reused_identity,
            ),
        ):
            cleanup_result = SHTEST.terminate_process_tree(
                process,
                set(),
                leader_identity,
                leader_group,
                budget,
            )
        self.assertFalse(cleanup_result.complete)
        self.assertTrue(cleanup_result.descendant_cleanup_required)
        self.assertIn(mock.call(reused_identity), signal_identity.call_args_list)

    def test_exact_original_leader_identity_is_excluded_from_direct_cleanup(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        leader_identity = (700000, 1000)
        leader_group = SHTEST.ProcessGroupIdentity(
            700000, 1000, 700000, 700000
        )
        snapshot = SHTEST.ProcessSnapshot(
            {os.getpid(): {700000}}, {700000: leader_identity}, True
        )
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
        with (
            mock.patch.object(SHTEST, "process_snapshot", return_value=snapshot),
            mock.patch.object(SHTEST, "signal_process_group", return_value=True),
            mock.patch.object(SHTEST, "signal_identity") as signal_identity,
            mock.patch.object(SHTEST, "reap_identities", return_value=True),
            mock.patch.object(SHTEST, "identity_is_running") as identity_is_running,
        ):
            cleanup_result = SHTEST.terminate_process_tree(
                process,
                set(),
                leader_identity,
                leader_group,
                budget,
            )
        self.assertTrue(cleanup_result.complete)
        self.assertFalse(cleanup_result.descendant_cleanup_required)
        signal_identity.assert_not_called()
        identity_is_running.assert_not_called()

    def test_missing_initial_leader_identity_reports_incomplete(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        leader_group = SHTEST.ProcessGroupIdentity(
            700000, 1000, 700000, 700000
        )
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
        with (
            mock.patch.object(SHTEST, "process_snapshot") as snapshot,
            mock.patch.object(SHTEST, "signal_process_group") as group_signal,
            mock.patch.object(SHTEST.os, "kill") as kill,
        ):
            snapshot.return_value = SHTEST.ProcessSnapshot({}, {}, True)
            cleanup_result = SHTEST.terminate_process_tree(
                process, set(), None, leader_group, budget
            )
            self.assertFalse(cleanup_result.complete)
            self.assertFalse(cleanup_result.descendant_cleanup_required)
        group_signal.assert_not_called()
        kill.assert_not_called()

    def test_mismatched_initial_leader_identity_reports_incomplete(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
        with (
            mock.patch.object(
                SHTEST, "process_identity", return_value=(700001, 1000)
            ),
            mock.patch.object(SHTEST, "process_snapshot") as snapshot,
            mock.patch.object(SHTEST, "signal_process_group") as group_signal,
            mock.patch.object(SHTEST.os, "kill") as kill,
        ):
            snapshot.return_value = SHTEST.ProcessSnapshot({}, {}, True)
            cleanup_result = SHTEST.terminate_process_tree(
                process, set(), (700001, 1000), None, budget
            )
            self.assertFalse(cleanup_result.complete)
            self.assertFalse(cleanup_result.descendant_cleanup_required)
        group_signal.assert_not_called()
        kill.assert_not_called()

    def test_mismatched_initial_group_identity_reports_incomplete(self) -> None:
        process = mock.Mock(pid=700000)
        process.poll.return_value = 0
        mismatched_group = SHTEST.ProcessGroupIdentity(
            700000, 2000, 700000, 700000
        )
        budget = SHTEST.TraversalBudget(time.monotonic() + 0.1)
        with (
            mock.patch.object(SHTEST, "process_identity", return_value=None),
            mock.patch.object(SHTEST, "process_snapshot") as snapshot,
            mock.patch.object(SHTEST, "signal_process_group") as group_signal,
            mock.patch.object(SHTEST.os, "kill") as kill,
        ):
            snapshot.return_value = SHTEST.ProcessSnapshot({}, {}, True)
            cleanup_result = SHTEST.terminate_process_tree(
                process,
                set(),
                (700000, 1000),
                mismatched_group,
                budget,
            )
            self.assertFalse(cleanup_result.complete)
            self.assertFalse(cleanup_result.descendant_cleanup_required)
        group_signal.assert_not_called()
        kill.assert_not_called()

    def test_infinite_stdout_and_stderr_are_capped_and_terminated(self) -> None:
        for mode, stream, byte in (
            ("stdout-flood", "stdout", b"x"),
            ("stderr-flood", "stderr", b"y"),
        ):
            with self.subTest(mode=mode):
                started = time.monotonic()
                completed, report, _ = self.run_harness(
                    [run_case(timeout=2)], mode
                )
                elapsed = time.monotonic() - started
                self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
                self.assertLess(elapsed, 1.5)
                entry = report["cases"][0]
                result = entry["candidate"]
                captured = base64.b64decode(result[f"{stream}_b64"])
                self.assertEqual(captured, byte * SHTEST.MAX_CAPTURE_BYTES)
                self.assertTrue(result[f"{stream}_truncated"])
                self.assertTrue(result["output_limit_exceeded"])
                self.assertFalse(result["cleanup_incomplete"])
                self.assertFalse(pathlib.Path(result["working_directory"]).exists())
                self.assertIn(
                    f"candidate {stream} exceeded {SHTEST.MAX_CAPTURE_BYTES}-byte capture limit",
                    entry["differences"],
                )
                self.assertLess(len(json.dumps(report)), 2 * SHTEST.MAX_CAPTURE_BYTES)

    def test_exact_bytes_at_capture_cap_are_not_truncated(self) -> None:
        completed, report, _ = self.run_harness(
            [run_case(argv=["at-cap"], timeout=2)]
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        for side in ("oracle", "candidate"):
            result = report["cases"][0][side]
            self.assertEqual(
                len(base64.b64decode(result["stdout_b64"])),
                SHTEST.MAX_CAPTURE_BYTES,
            )
            self.assertEqual(
                len(base64.b64decode(result["stderr_b64"])),
                SHTEST.MAX_CAPTURE_BYTES,
            )
            self.assertFalse(result["stdout_truncated"])
            self.assertFalse(result["stderr_truncated"])
            self.assertFalse(result["output_limit_exceeded"])

    def test_native_execution_image_fd_is_close_on_exec(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            helper = pathlib.Path(temporary) / "inspect_fds.py"
            helper.write_text(
                "import json,os\n"
                "targets=[]\n"
                "for name in os.listdir('/proc/self/fd'):\n"
                "  try: targets.append(os.readlink('/proc/self/fd/' + name))\n"
                "  except OSError: pass\n"
                "print(json.dumps(targets))\n",
                encoding="utf-8",
            )
            image = SHTEST.capture_executable(
                pathlib.Path(sys.executable).resolve(), "native-fd-test"
            )
            try:
                result = SHTEST.run_process(image, [str(helper)], b"", 2)
            finally:
                image.close()
        targets = json.loads(base64.b64decode(result.stdout_b64))
        self.assertFalse(any("memfd:shtest-native-fd-test" in item for item in targets))
        self.assertFalse(result.cleanup_incomplete)

    def test_skip_selection_listing_and_accounting_are_stable(self) -> None:
        cases = [run_case("z-last"), skip_case("a-skip"), run_case("m-middle")]
        completed, report, _ = self.run_harness(cases, patterns=["*-skip", "m-*"])
        self.assertEqual(completed.returncode, 0)
        self.assertEqual([entry["case"]["id"] for entry in report["cases"]], ["a-skip", "m-middle"])
        self.assertEqual(report["summary"]["skipped"], 1)
        self.assertEqual(report["summary"]["passed"], 1)

        with tempfile.TemporaryDirectory() as temporary:
            catalog = pathlib.Path(temporary) / "catalog.json"
            catalog.write_text(json.dumps({"schema_version": 1, "cases": cases}), encoding="utf-8")
            listed = subprocess.run(
                [sys.executable, str(RUNNER), "--catalog", str(catalog), "--list", "--case", "*-skip", "--case", "m-*"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
        self.assertEqual(listed.returncode, 0)
        self.assertEqual([line.split("\t")[0] for line in listed.stdout.splitlines()], ["a-skip", "m-middle"])

    def test_environment_is_secret_free_workdirs_are_isolated_and_cleaned(self) -> None:
        case = run_case(argv=["inspect", str(ROOT)])
        with mock.patch.dict(os.environ, {"SHTEST_TEST_SECRET": "must-not-leak"}):
            completed, report, _ = self.run_harness([case])
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        entry = report["cases"][0]
        self.assertEqual(base64.b64decode(entry["candidate"]["stdout_b64"]), b"isolated")
        oracle_cwd = pathlib.Path(entry["oracle"]["working_directory"])
        candidate_cwd = pathlib.Path(entry["candidate"]["working_directory"])
        self.assertNotEqual(oracle_cwd, candidate_cwd)
        self.assertFalse(oracle_cwd.exists())
        self.assertFalse(candidate_cwd.exists())

    def test_oracle_version_pin_and_candidate_clobber_safeguard(self) -> None:
        completed, report, _ = self.run_harness([run_case()], oracle_version="jq-1.7")
        self.assertEqual(completed.returncode, 2)
        self.assertIn("expected 'jq-1.8.1'", completed.stderr)
        self.assertEqual(report["schema_version"], 5)
        self.assertEqual(report["startup_failure"]["stage"], "version_identity")
        self.assertEqual(report["startup_failure"]["role"], "oracle")
        self.assertEqual(report["oracle"]["version"], "jq-1.7")
        self.assertEqual(report["oracle"]["version_process"]["exit_status"], 0)

        completed, report, _ = self.run_harness([run_case()], "clobber")
        self.assertEqual(completed.returncode, 1)
        self.assertEqual(report["cases"][0]["status"], "fail")
        self.assertEqual(base64.b64decode(report["cases"][0]["oracle"]["stdout_b64"]), b"out\x00\xff")

    def test_invalid_candidate_versions_fail_closed_before_candidate_cases(self) -> None:
        modes = (
            "version-nonzero",
            "version-signal",
            "version-no-newline",
            "version-multiline",
            "version-empty",
            "version-stderr",
            "version-nonutf8",
        )
        for mode in modes:
            with self.subTest(mode=mode):
                with tempfile.TemporaryDirectory() as temporary:
                    marker = pathlib.Path(temporary) / "case-executed"
                    completed, report, _ = self.run_harness(
                        [run_case()], mode, candidate_target=marker
                    )
                self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
                self.assertIn("HARNESS ERROR", completed.stderr)
                self.assertNotIn("SUMMARY", completed.stdout)
                self.assertEqual(report["schema_version"], 5)
                self.assertEqual(report["startup_failure"]["stage"], "version_probe")
                self.assertEqual(report["startup_failure"]["role"], "candidate")
                self.assertEqual(
                    report["startup_failure"]["process_result"],
                    report["candidate"]["version_process"],
                )
                self.assertFalse(marker.exists())

    def test_candidate_version_timeout_fails_closed_before_candidate_cases(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            marker = pathlib.Path(temporary) / "case-executed"
            started = time.monotonic()
            completed, report, _ = self.run_harness(
                [run_case()], "version-timeout", candidate_target=marker
            )
            elapsed = time.monotonic() - started
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        self.assertLess(elapsed, 7)
        self.assertIn("--version timed out", completed.stderr)
        self.assertNotIn("SUMMARY", completed.stdout)
        self.assertTrue(report["candidate"]["version_process"]["timed_out"])
        self.assertEqual(
            report["startup_failure"]["process_result"],
            report["candidate"]["version_process"],
        )
        self.assertFalse(marker.exists())

    def test_candidate_version_detached_child_is_killed_and_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            marker = pathlib.Path(temporary) / "version-detached.pid"
            completed, report, _ = self.run_harness(
                [run_case()],
                "version-detached-child",
                candidate_target=marker,
            )
            detached_pid = int(marker.read_text(encoding="ascii"))
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        self.assertIn("did not cleanly release", completed.stderr)
        self.assertNotIn("SUMMARY", completed.stdout)
        self.assertEqual(report["schema_version"], 5)
        self.assertEqual(report["startup_failure"]["stage"], "version_probe")
        self.assertEqual(report["startup_failure"]["role"], "candidate")
        version_process = report["candidate"]["version_process"]
        self.assertTrue(version_process["descendant_cleanup_required"])
        self.assertFalse(version_process["cleanup_incomplete"])
        self.assertEqual(
            report["startup_failure"]["process_result"], version_process
        )
        self.assertFalse(pathlib.Path(f"/proc/{detached_pid}").exists())

    def test_candidate_version_metadata_mutation_cannot_poison_later_execution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            marker = pathlib.Path(temporary) / "metadata-mutation"
            completed, report, _ = self.run_harness(
                [run_case()],
                "version-mutate-exec-mode",
                candidate_target=marker,
            )
            self.assertEqual(marker.read_text(encoding="ascii"), "metadata-protected")
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIsNone(report["startup_failure"])
        self.assertEqual(report["summary"]["passed"], 1)
        self.assertEqual(report["candidate"]["version_process"]["exit_status"], 0)
        self.assertEqual(report["cases"][0]["candidate"]["exit_status"], 0)

    def test_candidate_interpreter_replacement_cannot_change_later_execution(self) -> None:
        completed, report, _ = self.run_harness(
            [run_case()], "replace-interpreter"
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIsNone(report["startup_failure"])
        self.assertEqual(report["summary"]["passed"], 1)
        interpreter = report["candidate"]["interpreter"]
        self.assertEqual(interpreter["path"].rsplit("/", 1)[-1], "candidate-python")
        self.assertRegex(interpreter["sha256"], r"^[0-9a-f]{64}$")
        replacement_sha256 = hashlib.sha256(
            pathlib.Path("/bin/false").read_bytes()
        ).hexdigest()
        self.assertNotEqual(interpreter["sha256"], replacement_sha256)
        self.assertEqual(report["candidate"]["version_process"]["exit_status"], 0)
        self.assertEqual(report["cases"][0]["candidate"]["exit_status"], 0)

    def test_native_elf_interpreter_replacement_cannot_change_later_execution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            loader = directory / "candidate-loader"
            active_loader = SHTEST.active_dynamic_loader_path().resolve()
            shutil.copyfile(active_loader, loader)
            loader.chmod(0o755)
            original_loader = loader.read_bytes()
            replacement_loader = pathlib.Path("/bin/false").read_bytes()
            self.assertNotEqual(original_loader, replacement_loader)
            oracle = self.build_native_cli(directory, "oracle-native")
            candidate = self.build_native_cli(
                directory, "candidate-native", dynamic_linker=loader
            )
            catalog = directory / "catalog.json"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            report_path = directory / "report.json"
            original_prepare = SHTEST.prepare_path_launches
            launch_count_path = directory / "candidate-launch-count"

            def replace_before_later_case(
                launches: tuple[object, ...],
            ) -> None:
                paths = {
                    material.path
                    for launch in launches
                    for material in launch.materials
                }
                if candidate in paths:
                    candidate_launches = (
                        int(launch_count_path.read_text(encoding="ascii")) + 1
                        if launch_count_path.exists()
                        else 1
                    )
                    launch_count_path.write_text(
                        str(candidate_launches), encoding="ascii"
                    )
                    if candidate_launches == 2:
                        replacement = loader.with_suffix(".replacement")
                        replacement.write_bytes(replacement_loader)
                        replacement.chmod(0o755)
                        os.replace(replacement, loader)
                original_prepare(launches)

            with mock.patch.object(
                SHTEST, "prepare_path_launches", side_effect=replace_before_later_case
            ):
                status = SHTEST.main(
                    [
                        "--catalog",
                        str(catalog),
                        "--oracle",
                        str(oracle),
                        "--candidate",
                        str(candidate),
                        "--json-report",
                        str(report_path),
                    ]
                )
            report = json.loads(report_path.read_text(encoding="utf-8"))
            candidate_launches = int(
                launch_count_path.read_text(encoding="ascii")
            )
            candidate_sha256 = hashlib.sha256(candidate.read_bytes()).hexdigest()
            observed_loader_sha256 = hashlib.sha256(loader.read_bytes()).hexdigest()
            loader_path = str(loader)
            original_loader_sha256 = hashlib.sha256(original_loader).hexdigest()
            replacement_loader_sha256 = hashlib.sha256(replacement_loader).hexdigest()

        self.assertEqual(status, 0)
        self.assertEqual(candidate_launches, 2)
        self.assertEqual(report["summary"]["passed"], 1)
        self.assertEqual(observed_loader_sha256, replacement_loader_sha256)
        self.assertEqual(report["candidate"]["sha256"], candidate_sha256)
        native_interpreter = next(
            dependency
            for dependency in report["candidate"]["dependencies"]
            if dependency["path"] == loader_path
        )
        self.assertEqual(native_interpreter["path"], loader_path)
        self.assertEqual(native_interpreter["sha256"], original_loader_sha256)
        self.assertNotEqual(native_interpreter["sha256"], replacement_loader_sha256)

    def test_host_candidate_replacement_after_capture_cannot_change_execution(
        self,
    ) -> None:
        (
            status,
            report,
            candidate,
            original_bytes,
            replacement_bytes,
            handshake,
        ) = self.run_harness_with_synchronized_host_replacement(
            replace_interpreter=False
        )

        original_sha256 = hashlib.sha256(original_bytes).hexdigest()
        replacement_sha256 = hashlib.sha256(replacement_bytes).hexdigest()
        self.assertEqual(status, 0)
        self.assertEqual(
            handshake, ["namespace-ready", "host-replaced", "child-released"]
        )
        self.assertEqual(candidate.read_bytes(), replacement_bytes)
        self.assertNotEqual(replacement_sha256, original_sha256)
        self.assertEqual(report["candidate"]["sha256"], original_sha256)
        self.assertNotEqual(report["candidate"]["sha256"], replacement_sha256)
        self.assertEqual(
            base64.b64decode(report["candidate"]["version_process"]["stdout_b64"]),
            b"jq-1.8.1\n",
        )
        self.assertEqual(
            base64.b64decode(report["cases"][0]["candidate"]["stdout_b64"]),
            b"out\x00\xff",
        )
        self.assertEqual(report["summary"]["passed"], 1)

    def test_host_interpreter_replacement_after_capture_cannot_change_execution(
        self,
    ) -> None:
        (
            status,
            report,
            interpreter_path,
            original_bytes,
            replacement_bytes,
            handshake,
        ) = self.run_harness_with_synchronized_host_replacement(
            replace_interpreter=True
        )

        original_sha256 = hashlib.sha256(original_bytes).hexdigest()
        replacement_sha256 = hashlib.sha256(replacement_bytes).hexdigest()
        self.assertEqual(status, 0)
        self.assertEqual(
            handshake, ["namespace-ready", "host-replaced", "child-released"]
        )
        self.assertEqual(interpreter_path.read_bytes(), replacement_bytes)
        self.assertNotEqual(replacement_sha256, original_sha256)
        self.assertEqual(
            report["candidate"]["interpreter"]["sha256"], original_sha256
        )
        self.assertNotEqual(
            report["candidate"]["interpreter"]["sha256"], replacement_sha256
        )
        self.assertEqual(
            base64.b64decode(report["candidate"]["version_process"]["stdout_b64"]),
            b"jq-1.8.1\n",
        )
        self.assertEqual(
            base64.b64decode(report["cases"][0]["candidate"]["stdout_b64"]),
            b"out\x00\xff",
        )
        self.assertEqual(report["summary"]["passed"], 1)

    def test_containment_loss_stops_before_a_second_untrusted_invocation(self) -> None:
        def process_result(*, cleanup_incomplete: bool) -> object:
            return SHTEST.ProcessResult(
                argv=["sealed", "success"],
                working_directory="/tmp/quarantine",
                exit_status=0,
                signal=None,
                timed_out=False,
                duration_ms=1,
                stdout_b64=b64(b"out\x00\xff"),
                stderr_b64=b64(b"err\xfe"),
                stdout_truncated=False,
                stderr_truncated=False,
                output_limit_exceeded=False,
                pipe_drain_timed_out=False,
                descendant_cleanup_required=False,
                cleanup_incomplete=cleanup_incomplete,
                quarantined_path=("/tmp/quarantine" if cleanup_incomplete else None),
            )

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            report_path = directory / "report.json"
            catalog.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "cases": [run_case("first"), run_case("second")],
                    }
                ),
                encoding="utf-8",
            )
            images = [
                mock.Mock(
                    label=role,
                    sha256=role[0] * 64,
                    source_device=index,
                    source_inode=index + 10,
                )
                for index, role in enumerate(("oracle", "candidate"), 1)
            ]
            clean_probe = process_result(cleanup_incomplete=False)
            lost_containment = process_result(cleanup_incomplete=True)
            invocations = 0

            def run_once(*args: object, **kwargs: object) -> object:
                nonlocal invocations
                invocations += 1
                return lost_containment

            with (
                mock.patch.object(SHTEST, "capture_executable", side_effect=images),
                mock.patch.object(
                    SHTEST,
                    "version_of",
                    side_effect=[
                        ("jq-1.8.1", clean_probe),
                        ("jq-1.8.1", clean_probe),
                    ],
                ),
                mock.patch.object(SHTEST, "run_process", side_effect=run_once),
                mock.patch("builtins.print"),
            ):
                status = SHTEST.main(
                    [
                        "--catalog",
                        str(catalog),
                        "--oracle",
                        str(directory / "oracle"),
                        "--candidate",
                        str(directory / "candidate"),
                        "--json-report",
                        str(report_path),
                    ]
                )
            report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertEqual(status, 2)
        self.assertEqual(invocations, 1)
        self.assertEqual(report["startup_failure"]["stage"], "oracle_case_execution")
        self.assertEqual(report["startup_failure"]["role"], "oracle")
        self.assertEqual(
            report["startup_failure"]["process_result"],
            SHTEST.asdict(lost_containment),
        )

    def test_late_containment_loss_preserves_completed_case_results(self) -> None:
        def process_result(
            stdout: bytes, *, cleanup_incomplete: bool = False
        ) -> object:
            return SHTEST.ProcessResult(
                argv=["sealed", "success"],
                working_directory="/tmp/quarantine",
                exit_status=0,
                signal=None,
                timed_out=False,
                duration_ms=1,
                stdout_b64=b64(stdout),
                stderr_b64=b64(b""),
                stdout_truncated=False,
                stderr_truncated=False,
                output_limit_exceeded=False,
                pipe_drain_timed_out=False,
                descendant_cleanup_required=False,
                cleanup_incomplete=cleanup_incomplete,
                quarantined_path=(
                    "/tmp/quarantine" if cleanup_incomplete else None
                ),
            )

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            report_path = directory / "report.json"
            catalog.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "cases": [run_case("first"), run_case("second")],
                    }
                ),
                encoding="utf-8",
            )
            images = [
                mock.Mock(
                    label=role,
                    sha256=role[0] * 64,
                    source_device=index,
                    source_inode=index + 10,
                )
                for index, role in enumerate(("oracle", "candidate"), 1)
            ]
            matching = process_result(b"oracle")
            mismatch = process_result(b"candidate-mismatch")
            lost_containment = process_result(
                b"second-candidate", cleanup_incomplete=True
            )

            with (
                mock.patch.object(SHTEST, "capture_executable", side_effect=images),
                mock.patch.object(
                    SHTEST,
                    "version_of",
                    side_effect=[
                        ("jq-1.8.1", matching),
                        ("jq-1.8.1", matching),
                    ],
                ),
                mock.patch.object(
                    SHTEST,
                    "run_process",
                    side_effect=[matching, matching, mismatch, lost_containment],
                ),
                mock.patch("builtins.print"),
            ):
                status = SHTEST.main(
                    [
                        "--catalog",
                        str(catalog),
                        "--oracle",
                        str(directory / "oracle"),
                        "--candidate",
                        str(directory / "candidate"),
                        "--json-report",
                        str(report_path),
                    ]
                )
            report = json.loads(report_path.read_text(encoding="utf-8"))

        self.assertEqual(status, 2)
        self.assertEqual(report["schema_version"], 5)
        self.assertEqual(
            report["summary"],
            {"selected": 2, "passed": 0, "failed": 1, "skipped": 0, "errors": 1},
        )
        self.assertEqual(len(report["cases"]), 1)
        completed = report["cases"][0]
        self.assertEqual(completed["case"]["id"], "first")
        self.assertEqual(completed["status"], "fail")
        self.assertIn("stdout bytes differ", completed["differences"])
        self.assertEqual(
            base64.b64decode(completed["candidate"]["stdout_b64"]),
            b"candidate-mismatch",
        )
        self.assertEqual(report["startup_failure"]["stage"], "case_execution")
        self.assertEqual(report["startup_failure"]["role"], "candidate")
        self.assertEqual(
            report["startup_failure"]["process_result"],
            SHTEST.asdict(lost_containment),
        )

    def test_candidate_version_identity_mismatch_fails_closed(self) -> None:
        completed, report, _ = self.run_harness(
            [run_case()], candidate_version="jq-1.7"
        )
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        self.assertIn("expected oracle identity 'jq-1.8.1'", completed.stderr)
        self.assertNotIn("SUMMARY", completed.stdout)
        self.assertEqual(report["startup_failure"]["stage"], "version_identity")
        self.assertEqual(report["startup_failure"]["role"], "candidate")
        self.assertIsNone(report["startup_failure"]["process_result"])
        self.assertEqual(report["candidate"]["version"], "jq-1.7")
        self.assertEqual(report["candidate"]["version_process"]["exit_status"], 0)

    def test_candidate_version_cleanup_error_fails_closed(self) -> None:
        result = SHTEST.ProcessResult(
            argv=["candidate", "--version"],
            working_directory="/tmp/removed",
            exit_status=0,
            signal=None,
            timed_out=False,
            duration_ms=1,
            stdout_b64=b64(b"jq-1.8.1\n"),
            stderr_b64=b64(b""),
            stdout_truncated=False,
            stderr_truncated=False,
            output_limit_exceeded=False,
            pipe_drain_timed_out=False,
            descendant_cleanup_required=False,
            cleanup_incomplete=True,
            quarantined_path="/tmp/shtest-quarantine-hostile",
        )
        executable = mock.Mock(path=pathlib.Path("candidate"))
        with mock.patch.object(SHTEST, "run_process", return_value=result):
            with self.assertRaisesRegex(
                SHTEST.VersionProbeError, "did not cleanly release"
            ) as raised:
                SHTEST.version_of(executable, 5.0, "candidate")
        self.assertIs(raised.exception.result, result)
        self.assertEqual(
            raised.exception.result.quarantined_path,
            "/tmp/shtest-quarantine-hostile",
        )

    def test_version_cleanup_failure_report_is_complete_and_repeatable(self) -> None:
        def process_result(*, quarantine: str | None = None) -> object:
            return SHTEST.ProcessResult(
                argv=["sealed", "--version"],
                working_directory=quarantine or "/tmp/removed",
                exit_status=0,
                signal=None,
                timed_out=False,
                duration_ms=1,
                stdout_b64=b64(b"jq-1.8.1\n"),
                stderr_b64=b64(b""),
                stdout_truncated=False,
                stderr_truncated=False,
                output_limit_exceeded=False,
                pipe_drain_timed_out=False,
                descendant_cleanup_required=False,
                cleanup_incomplete=quarantine is not None,
                quarantined_path=quarantine,
            )

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            catalog = directory / "catalog.json"
            catalog.write_text(
                json.dumps({"schema_version": 1, "cases": [run_case()]}),
                encoding="utf-8",
            )
            oracle_path = directory / "oracle"
            candidate_path = directory / "candidate"
            for path in (oracle_path, candidate_path):
                path.write_bytes(b"placeholder")

            for repetition in range(3):
                quarantine = f"/tmp/shtest-quarantine-repeat-{repetition}"
                oracle_probe = process_result()
                candidate_probe = process_result(quarantine=quarantine)
                oracle_image = mock.Mock(
                    sha256="a" * 64,
                    source_device=1,
                    source_inode=2,
                )
                candidate_image = mock.Mock(
                    sha256="b" * 64,
                    source_device=3,
                    source_inode=4,
                )
                report_path = directory / f"failure-{repetition}.json"
                failure = SHTEST.VersionProbeError(
                    "candidate --version cleanup incomplete",
                    "candidate",
                    candidate_probe,
                )
                with (
                    mock.patch.object(
                        SHTEST,
                        "capture_executable",
                        side_effect=[oracle_image, candidate_image],
                    ),
                    mock.patch.object(
                        SHTEST,
                        "version_of",
                        side_effect=[("jq-1.8.1", oracle_probe), failure],
                    ),
                    mock.patch.object(SHTEST, "run_process", return_value=oracle_probe),
                    mock.patch("builtins.print"),
                ):
                    status = SHTEST.main(
                        [
                            "--catalog",
                            str(catalog),
                            "--oracle",
                            str(oracle_path),
                            "--candidate",
                            str(candidate_path),
                            "--json-report",
                            str(report_path),
                        ]
                    )
                self.assertEqual(status, 2)
                report = json.loads(report_path.read_text(encoding="utf-8"))
                self.assertEqual(report["schema_version"], 5)
                self.assertEqual(report["summary"]["errors"], 1)
                self.assertEqual(report["startup_failure"]["stage"], "version_probe")
                self.assertEqual(report["startup_failure"]["role"], "candidate")
                self.assertEqual(
                    report["startup_failure"]["process_result"],
                    report["candidate"]["version_process"],
                )
                self.assertTrue(
                    report["candidate"]["version_process"]["cleanup_incomplete"]
                )
                self.assertEqual(
                    report["candidate"]["version_process"]["quarantined_path"],
                    quarantine,
                )
                oracle_image.close.assert_called_once_with()
                candidate_image.close.assert_called_once_with()

    def test_self_replacing_version_executes_and_reports_sealed_original_bytes(self) -> None:
        completed, report, directory = self.run_harness(
            [run_case()], "self-replace"
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        candidate = directory / "candidate"
        self.assertEqual(report["candidate"]["sha256"], self.candidate_original_sha256)
        self.assertEqual(candidate.read_bytes(), self.candidate_original_bytes)
        self.assertEqual(
            base64.b64decode(report["cases"][0]["candidate"]["stdout_b64"]),
            b"out\x00\xff",
        )
        self.assertFalse((directory / "candidate.replacement").exists())
        self.assertFalse(
            pathlib.Path(report["cases"][0]["candidate"]["working_directory"]).exists()
        )

    def test_production_catalog_loads_and_has_explicit_pipeline_skips(self) -> None:
        cases = SHTEST.load_catalog(ROOT / "compat/shtest-process.json")
        self.assertGreaterEqual(len(cases), 25)
        skips = {case.case_id: case.skip_reason for case in cases if case.kind == "skip"}
        self.assertIn("constant-folding-disassembly-loop", skips)
        self.assertIn("large-exponent-two-process-pipeline", skips)
        self.assertTrue(all(skips.values()))


if __name__ == "__main__":
    unittest.main()
