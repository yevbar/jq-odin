#!/usr/bin/env python3
"""Run jq.test cases against a pinned jq oracle and a candidate CLI."""

from __future__ import annotations

import argparse
import base64
import decimal
import fnmatch
import hashlib
import json
import math
import os
import pathlib
import platform
import shlex
import signal
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from typing import Any, Iterable


SCHEMA_VERSION = 1
EXPECTED_ORACLE_VERSION = "jq-1.8.1"
STABLE_ENVIRONMENT = {
    "LANG": "C",
    "LC_ALL": "C",
    "NO_COLOR": "1",
    "PATH": os.defpath,
    "TMPDIR": "/tmp",
    "TZ": "UTC",
}


class HarnessError(Exception):
    pass


class DuplicateObjectKeyError(ValueError):
    pass


@dataclass(frozen=True)
class TestCase:
    ordinal: int
    case_id: str
    source: str
    line: int
    kind: str
    program: str
    input_text: str | None
    fixture_outputs: list[str]
    fixture_diagnostics: list[str]
    ignore_diagnostics: bool


@dataclass
class ProcessResult:
    argv: list[str]
    returncode: int | None
    signal: int | None
    timed_out: bool
    duration_ms: int
    stdout_b64: str
    stderr_b64: str
    stdout_text: str
    stderr_text: str


def repository_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[2]


def display_source(path: pathlib.Path, root: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def skipped_line(line: str) -> bool:
    stripped = line.lstrip(" \t")
    return stripped == "" or stripped.startswith("#")


def parse_jq_test(path: pathlib.Path, root: pathlib.Path | None = None) -> list[TestCase]:
    root = root or repository_root()
    try:
        lines = path.read_text(encoding="utf-8").split("\n")
    except (OSError, UnicodeError) as exc:
        raise HarnessError(f"cannot read test suite {path}: {exc}") from exc

    source = display_source(path, root)
    cases: list[TestCase] = []
    index = 0
    failure_marker: tuple[bool, int] | None = None

    while index < len(lines):
        line = lines[index]
        line_number = index + 1
        index += 1

        if skipped_line(line):
            continue
        if line in ("%%FAIL", "%%FAIL IGNORE MSG"):
            if failure_marker is not None:
                raise HarnessError(
                    f"{source}:{line_number}: nested failure marker"
                )
            failure_marker = (line == "%%FAIL IGNORE MSG", line_number)
            continue

        program = line
        program_line = line_number
        ordinal = len(cases) + 1
        case_id = f"{source}:{program_line}"

        if failure_marker is not None:
            diagnostics: list[str] = []
            while index < len(lines) and not skipped_line(lines[index]):
                diagnostics.append(lines[index])
                index += 1
            cases.append(
                TestCase(
                    ordinal=ordinal,
                    case_id=case_id,
                    source=source,
                    line=program_line,
                    kind="compile-fail",
                    program=program,
                    input_text=None,
                    fixture_outputs=[],
                    fixture_diagnostics=diagnostics,
                    ignore_diagnostics=failure_marker[0],
                )
            )
            failure_marker = None
            continue

        if index >= len(lines):
            raise HarnessError(f"{case_id}: missing input line")

        input_text = lines[index]
        index += 1
        fixture_outputs: list[str] = []
        while index < len(lines) and not skipped_line(lines[index]):
            fixture_outputs.append(lines[index])
            index += 1

        cases.append(
            TestCase(
                ordinal=ordinal,
                case_id=case_id,
                source=source,
                line=program_line,
                kind="execute",
                program=program,
                input_text=input_text,
                fixture_outputs=fixture_outputs,
                fixture_diagnostics=[],
                ignore_diagnostics=False,
            )
        )

    if failure_marker is not None:
        raise HarnessError(
            f"{source}:{failure_marker[1]}: failure marker has no program"
        )
    if not cases:
        raise HarnessError(f"test suite contains no cases: {source}")
    return cases


def load_skips(path: pathlib.Path, known_ids: set[str]) -> dict[str, str]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise HarnessError(f"cannot read skip manifest {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise HarnessError(f"skip manifest must be a JSON object: {path}")

    skips: dict[str, str] = {}
    for case_id, reason in value.items():
        if not isinstance(case_id, str) or not isinstance(reason, str) or not reason:
            raise HarnessError("skip entries must map case IDs to non-empty reasons")
        if case_id not in known_ids:
            raise HarnessError(f"skip manifest names unknown case: {case_id}")
        skips[case_id] = reason
    return skips


def version_of(
    executable: pathlib.Path,
    timeout: float,
    cwd: pathlib.Path,
    require_clean: bool = False,
) -> str:
    result = run_process(
        [str(executable), "--version"],
        b"",
        cwd,
        timeout,
    )
    if result.timed_out:
        raise HarnessError(f"{executable} --version timed out")
    stdout = base64.b64decode(result.stdout_b64)
    stderr = base64.b64decode(result.stderr_b64)
    if require_clean:
        if result.returncode != 0 or result.signal is not None:
            raise HarnessError(
                f"oracle --version exited with status {result.returncode} "
                f"and signal {result.signal}"
            )
        if stderr:
            raise HarnessError("oracle --version wrote to stderr")
        if not stdout.endswith(b"\n") or stdout.count(b"\n") != 1:
            raise HarnessError(
                "oracle --version must emit exactly one LF-terminated line"
            )
        try:
            return stdout[:-1].decode("utf-8")
        except UnicodeDecodeError as exc:
            raise HarnessError("oracle --version is not UTF-8") from exc
    output = (stdout or stderr).decode("utf-8", errors="replace")
    return output.strip()


def encoded(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def run_process(
    argv: list[str],
    stdin: bytes,
    cwd: pathlib.Path,
    timeout: float,
) -> ProcessResult:
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            env=STABLE_ENVIRONMENT,
            start_new_session=True,
        )
        stdout, stderr = process.communicate(input=stdin, timeout=timeout)
        duration_ms = round((time.monotonic() - started) * 1000)
        returncode = process.returncode
        termination_signal = -returncode if returncode < 0 else None
        return ProcessResult(
            argv=argv,
            returncode=returncode,
            signal=termination_signal,
            timed_out=False,
            duration_ms=duration_ms,
            stdout_b64=encoded(stdout),
            stderr_b64=encoded(stderr),
            stdout_text=stdout.decode("utf-8", errors="replace"),
            stderr_text=stderr.decode("utf-8", errors="replace"),
        )
    except subprocess.TimeoutExpired as exc:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if process.poll() is None:
            process.kill()
        process.wait()
        if process.stdout is not None:
            process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()
        duration_ms = round((time.monotonic() - started) * 1000)
        stdout = exc.stdout or b""
        stderr = exc.stderr or b""
        return ProcessResult(
            argv=argv,
            returncode=None,
            signal=None,
            timed_out=True,
            duration_ms=duration_ms,
            stdout_b64=encoded(stdout),
            stderr_b64=encoded(stderr),
            stdout_text=stdout.decode("utf-8", errors="replace"),
            stderr_text=stderr.decode("utf-8", errors="replace"),
        )
    except OSError as exc:
        raise HarnessError(f"cannot execute {shlex.join(argv)}: {exc}") from exc


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise HarnessError(f"cannot hash oracle {path}: {exc}") from exc
    return digest.hexdigest()


def semantic_equal(left: Any, right: Any) -> bool:
    number_types = (int, float, decimal.Decimal)
    left_is_number = isinstance(left, number_types) and not isinstance(left, bool)
    right_is_number = isinstance(right, number_types) and not isinstance(right, bool)
    left_is_nan = (
        isinstance(left, float) and math.isnan(left)
    ) or (
        isinstance(left, decimal.Decimal) and left.is_nan()
    )
    right_is_nan = (
        isinstance(right, float) and math.isnan(right)
    ) or (
        isinstance(right, decimal.Decimal) and right.is_nan()
    )
    if left_is_nan or right_is_nan:
        return left_is_nan and right_is_nan
    if left_is_number and right_is_number:
        return left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, list):
        return len(left) == len(right) and all(
            semantic_equal(a, b) for a, b in zip(left, right)
        )
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(
            semantic_equal(left[key], right[key]) for key in left
        )
    return left == right


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, member in pairs:
        if key in value:
            raise DuplicateObjectKeyError(key)
        value[key] = member
    return value


def json_stream(result: ProcessResult) -> tuple[list[Any] | None, str | None]:
    try:
        text = base64.b64decode(result.stdout_b64).decode("utf-8")
    except UnicodeDecodeError as exc:
        return None, f"stdout is not UTF-8: byte {exc.start}"
    if text == "":
        return [], None
    if not text.endswith("\n"):
        return None, "stdout does not end with a newline"

    values: list[Any] = []
    # jq delimits compact JSON values with byte LF. str.splitlines() also
    # splits valid JSON string contents such as U+0085 and U+2028.
    for line_number, line in enumerate(text[:-1].split("\n"), start=1):
        if line == "":
            return None, f"stdout contains an empty line at output {line_number}"
        try:
            values.append(
                json.loads(
                    line,
                    parse_float=decimal.Decimal,
                    parse_constant=decimal.Decimal,
                    object_pairs_hook=unique_object,
                )
            )
        except DuplicateObjectKeyError as exc:
            return (
                None,
                f"stdout output {line_number} contains duplicate object "
                f"member {str(exc)!r}",
            )
        except json.JSONDecodeError as exc:
            return None, f"stdout output {line_number} is not JSON: {exc.msg}"
    return values, None


def compare_case(
    case: TestCase,
    oracle: ProcessResult,
    candidate: ProcessResult,
) -> list[str]:
    differences: list[str] = []

    if oracle.timed_out:
        return ["oracle timed out"]
    if candidate.timed_out:
        differences.append("candidate timed out")
        return differences

    if oracle.returncode != candidate.returncode:
        differences.append(
            f"exit status differs: oracle={oracle.returncode}, "
            f"candidate={candidate.returncode}"
        )
    if oracle.signal != candidate.signal:
        differences.append(
            f"signal differs: oracle={oracle.signal}, candidate={candidate.signal}"
        )

    if case.kind == "execute":
        oracle_values, oracle_error = json_stream(oracle)
        candidate_values, candidate_error = json_stream(candidate)
        if oracle_error:
            differences.append(f"oracle harness error: {oracle_error}")
        if candidate_error:
            differences.append(candidate_error)
        if oracle_values is not None and candidate_values is not None:
            if len(oracle_values) != len(candidate_values):
                differences.append(
                    f"output count differs: oracle={len(oracle_values)}, "
                    f"candidate={len(candidate_values)}"
                )
            else:
                for output_index, (expected, actual) in enumerate(
                    zip(oracle_values, candidate_values), start=1
                ):
                    if not semantic_equal(expected, actual):
                        differences.append(
                            f"output {output_index} differs: "
                            f"oracle={expected!r}, candidate={actual!r}"
                        )
        if oracle.stderr_b64 != candidate.stderr_b64:
            differences.append("stderr bytes differ")
    else:
        if oracle.returncode == 0:
            differences.append("oracle compiled a fixture marked %%FAIL")
        if candidate.returncode == 0:
            differences.append("candidate compiled a fixture marked %%FAIL")
        if not case.ignore_diagnostics and oracle.stderr_b64 != candidate.stderr_b64:
            differences.append("compile diagnostic bytes differ")
        if oracle.stdout_b64 != candidate.stdout_b64:
            differences.append("compile-failure stdout bytes differ")

    return differences


def command_for(
    executable: pathlib.Path,
    extra_args: list[str],
    module_path: pathlib.Path,
    program: str,
) -> list[str]:
    return [
        str(executable),
        *extra_args,
        "-L",
        str(module_path),
        "-c",
        "--",
        program,
    ]


def process_json(result: ProcessResult) -> dict[str, Any]:
    return asdict(result)


def case_json(case: TestCase) -> dict[str, Any]:
    stdin = (
        b""
        if case.input_text is None
        else (case.input_text + "\n").encode("utf-8")
    )
    value = asdict(case)
    value["stdin_b64"] = encoded(stdin)
    if case.kind == "execute":
        value["comparison_mode"] = "ordered-semantic-json"
    elif case.ignore_diagnostics:
        value["comparison_mode"] = "compile-failure-ignore-diagnostics"
    else:
        value["comparison_mode"] = "compile-failure-exact"
    value["capability_labels"] = ["core-language", case.kind]
    return value


def selected_cases(
    cases: list[TestCase],
    patterns: list[str],
    shard_count: int,
    shard_index: int,
    limit: int | None,
) -> list[TestCase]:
    selected: Iterable[TestCase] = cases
    if patterns:
        selected = [
            case
            for case in selected
            if any(fnmatch.fnmatchcase(case.case_id, pattern) for pattern in patterns)
        ]
    selected = [
        case
        for case in selected
        if (case.ordinal - 1) % shard_count == shard_index
    ]
    if limit is not None:
        selected = list(selected)[:limit]
    return list(selected)


def print_failure(
    case: TestCase,
    differences: list[str],
    oracle: ProcessResult,
    candidate: ProcessResult,
) -> None:
    print(f"FAIL {case.case_id} [{case.kind}]")
    for difference in differences:
        print(f"  - {difference}")
    print(f"  oracle:    {shlex.join(oracle.argv)}")
    print(f"  candidate: {shlex.join(candidate.argv)}")
    if oracle.stdout_text != candidate.stdout_text:
        print(f"  oracle stdout:    {oracle.stdout_text!r}")
        print(f"  candidate stdout: {candidate.stdout_text!r}")
    if oracle.stderr_text != candidate.stderr_text:
        print(f"  oracle stderr:    {oracle.stderr_text!r}")
        print(f"  candidate stderr: {candidate.stderr_text!r}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    root = repository_root()
    parser = argparse.ArgumentParser(
        description="Compare a jq-compatible candidate with pinned jq case by case."
    )
    parser.add_argument("--candidate", required=True, type=pathlib.Path)
    parser.add_argument("--oracle", required=True, type=pathlib.Path)
    parser.add_argument(
        "--tests",
        type=pathlib.Path,
        default=root / "upstream/jq/tests/jq.test",
    )
    parser.add_argument(
        "--module-path",
        type=pathlib.Path,
        default=root / "upstream/jq/tests/modules",
    )
    parser.add_argument(
        "--skips",
        type=pathlib.Path,
        default=root / "compat/skips.json",
    )
    parser.add_argument("--case", action="append", default=[], dest="patterns")
    parser.add_argument("--candidate-arg", action="append", default=[])
    parser.add_argument("--oracle-arg", action="append", default=[])
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--shard-count", type=int, default=1)
    parser.add_argument("--shard-index", type=int, default=0)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--json-report", type=pathlib.Path)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--show-passes", action="store_true")
    parser.add_argument("--allow-unpinned-oracle", action="store_true")
    args = parser.parse_args(argv)

    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    if args.shard_count <= 0:
        parser.error("--shard-count must be greater than zero")
    if not 0 <= args.shard_index < args.shard_count:
        parser.error("--shard-index must be in [0, shard-count)")
    if args.limit is not None and args.limit <= 0:
        parser.error("--limit must be greater than zero")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    root = repository_root()
    args.candidate = args.candidate.resolve()
    args.oracle = args.oracle.resolve()
    args.tests = args.tests.resolve()
    args.module_path = args.module_path.resolve()
    args.skips = args.skips.resolve()

    try:
        cases = parse_jq_test(args.tests, root)
        skips = load_skips(args.skips, {case.case_id for case in cases})
        selected = selected_cases(
            cases,
            args.patterns,
            args.shard_count,
            args.shard_index,
            args.limit,
        )
        if not selected:
            raise HarnessError("selection contains no test cases")

        if args.list:
            for case in selected:
                print(f"{case.case_id}\t{case.kind}\t{case.program}")
            return 0

        oracle_sha256 = sha256_file(args.oracle)
        oracle_version = version_of(
            args.oracle,
            args.timeout,
            root,
            require_clean=True,
        )
        if (
            not args.allow_unpinned_oracle
            and oracle_version != EXPECTED_ORACLE_VERSION
        ):
            raise HarnessError(
                f"oracle reports {oracle_version!r}; "
                f"expected {EXPECTED_ORACLE_VERSION!r}"
            )

        # The candidate is untrusted. Capture the entire oracle side before
        # launching even candidate --version, so candidate code cannot replace
        # the oracle path and influence any reference observation.
        oracle_results: dict[str, ProcessResult] = {}
        for case in selected:
            if case.case_id in skips:
                continue
            case_record = case_json(case)
            stdin = base64.b64decode(case_record["stdin_b64"])
            oracle_command = command_for(
                args.oracle, args.oracle_arg, args.module_path, case.program
            )
            oracle_results[case.case_id] = run_process(
                oracle_command, stdin, root, args.timeout
            )
        if sha256_file(args.oracle) != oracle_sha256:
            raise HarnessError("oracle executable changed while capturing results")

        candidate_version = version_of(args.candidate, args.timeout, root)
        results: list[dict[str, Any]] = []
        passed = failed = skipped = errors = 0
        for case in selected:
            if case.case_id in skips:
                skipped += 1
                reason = skips[case.case_id]
                print(f"SKIP {case.case_id}: {reason}")
                results.append(
                    {
                        "case": case_json(case),
                        "status": "skip",
                        "reason": reason,
                    }
                )
                continue

            case_record = case_json(case)
            stdin = base64.b64decode(case_record["stdin_b64"])
            candidate_command = command_for(
                args.candidate, args.candidate_arg, args.module_path, case.program
            )

            oracle_result = oracle_results[case.case_id]
            candidate_result = run_process(
                candidate_command, stdin, root, args.timeout
            )
            differences = compare_case(case, oracle_result, candidate_result)
            harness_error = any(
                difference.startswith("oracle harness error")
                or difference == "oracle timed out"
                or difference == "oracle compiled a fixture marked %%FAIL"
                for difference in differences
            )

            if not differences:
                status = "pass"
                passed += 1
                if args.show_passes:
                    print(f"PASS {case.case_id}")
            elif harness_error:
                status = "error"
                errors += 1
                print_failure(
                    case, differences, oracle_result, candidate_result
                )
            else:
                status = "fail"
                failed += 1
                print_failure(
                    case, differences, oracle_result, candidate_result
                )

            results.append(
                {
                    "case": case_record,
                    "status": status,
                    "differences": differences,
                    "oracle": process_json(oracle_result),
                    "candidate": process_json(candidate_result),
                }
            )

        summary = {
            "selected": len(selected),
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "errors": errors,
        }
        report = {
            "schema_version": SCHEMA_VERSION,
            "suite": display_source(args.tests, root),
            "execution": {
                "working_directory": str(root),
                "module_path": str(args.module_path.resolve()),
                "timeout_seconds": args.timeout,
                "environment": STABLE_ENVIRONMENT,
                "inherits_host_environment": False,
            },
            "platform": {
                "system": platform.system(),
                "release": platform.release(),
                "machine": platform.machine(),
                "python": platform.python_version(),
            },
            "normalization_rules": [
                "stdout is an LF-delimited ordered stream of compact JSON values",
                "JSON object member order and insignificant number formatting are ignored",
                "duplicate JSON object members are rejected",
                "output order and cardinality are preserved",
                "stderr, compile-failure stdout, exit status, and signal are exact",
                "%%FAIL IGNORE MSG omits only compile diagnostic comparison",
            ],
            "oracle": {
                "path": str(args.oracle.resolve()),
                "version": oracle_version,
                "sha256": oracle_sha256,
                "extra_args": args.oracle_arg,
            },
            "candidate": {
                "path": str(args.candidate.resolve()),
                "version": candidate_version,
                "extra_args": args.candidate_arg,
            },
            "selection": {
                "patterns": args.patterns,
                "shard_count": args.shard_count,
                "shard_index": args.shard_index,
                "limit": args.limit,
            },
            "summary": summary,
            "cases": results,
        }

        if args.json_report:
            args.json_report.parent.mkdir(parents=True, exist_ok=True)
            args.json_report.write_text(
                json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )

        print(
            "SUMMARY "
            f"selected={len(selected)} passed={passed} failed={failed} "
            f"skipped={skipped} errors={errors}"
        )
        if errors:
            return 2
        return 1 if failed else 0
    except HarnessError as exc:
        print(f"HARNESS ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
