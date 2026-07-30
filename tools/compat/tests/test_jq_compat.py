#!/usr/bin/env python3

from __future__ import annotations

import base64
import decimal
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[3]
RUNNER = ROOT / "tools/compat/jq_compat.py"
SPEC = importlib.util.spec_from_file_location("jq_compat", RUNNER)
assert SPEC is not None and SPEC.loader is not None
JQ_COMPAT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = JQ_COMPAT
SPEC.loader.exec_module(JQ_COMPAT)


SUITE = """\
# normal
.
{"x": 1}
{"x":1}

.two
null
1
2

empty
null

%%FAIL
compile_fail
jq: error: compile failure

%%FAIL IGNORE MSG
compile_fail_ignored
message intentionally ignored
"""


FAKE_CLI = """\
#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
import time

MODE = {mode!r}
TARGET = {target!r}

if sys.argv[1:] == ["--version"]:
    if MODE == "clobber_version":
        shutil.copyfile(sys.argv[0], TARGET)
        pathlib_mode = 0o755
        __import__("os").chmod(TARGET, pathlib_mode)
    if MODE == "bad_version_status":
        print("version warning", file=sys.stderr)
        print({version!r})
        raise SystemExit(3)
    if MODE == "bad_version_shape":
        sys.stdout.write({version!r})
        raise SystemExit(0)
    print({version!r})
    raise SystemExit(0)

program = sys.argv[-1]
stdin = sys.stdin.read()

if MODE == "hang_descendant":
    subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    time.sleep(60)

if program == ".":
    value = json.loads(stdin)
    if MODE == "clobber_version":
        value = None
    print(json.dumps(value, separators=(",", ":")))
elif program == ".two":
    outputs = [1, 2]
    if MODE == "reverse":
        outputs.reverse()
    elif MODE == "omit":
        outputs.pop()
    for value in outputs:
        print(json.dumps(value))
elif program == "empty":
    pass
elif program in ("compile_fail", "compile_fail_ignored"):
    message = "jq: error: compile failure"
    if MODE == "diagnostic":
        message = "different diagnostic"
    print(message, file=sys.stderr)
    raise SystemExit(3)
else:
    print("unsupported fake filter", file=sys.stderr)
    raise SystemExit(2)
"""


class ParserTests(unittest.TestCase):
    def test_parser_preserves_cardinality_failures_and_lines(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            suite = pathlib.Path(directory) / "sample.test"
            suite.write_text(SUITE, encoding="utf-8")
            cases = JQ_COMPAT.parse_jq_test(suite, ROOT)

        self.assertEqual(len(cases), 5)
        self.assertEqual(cases[0].line, 2)
        self.assertEqual(cases[1].fixture_outputs, ["1", "2"])
        self.assertEqual(cases[2].fixture_outputs, [])
        self.assertEqual(cases[3].kind, "compile-fail")
        self.assertFalse(cases[3].ignore_diagnostics)
        self.assertTrue(cases[4].ignore_diagnostics)

    def test_parser_splits_only_physical_lf(self) -> None:
        suite_text = '.\n"before\u0085after\u2028still"\n"expected"\n\n'
        with tempfile.TemporaryDirectory() as directory:
            suite = pathlib.Path(directory) / "unicode.test"
            suite.write_text(suite_text, encoding="utf-8")
            cases = JQ_COMPAT.parse_jq_test(suite, ROOT)
        self.assertEqual(len(cases), 1)
        self.assertEqual(cases[0].input_text, '"before\u0085after\u2028still"')

    def test_semantic_comparison_treats_nan_as_equal(self) -> None:
        nan = float("nan")
        self.assertTrue(JQ_COMPAT.semantic_equal([nan], [nan]))
        self.assertFalse(JQ_COMPAT.semantic_equal([nan], [1]))
        self.assertFalse(JQ_COMPAT.semantic_equal(True, 1))
        self.assertFalse(
            JQ_COMPAT.semantic_equal(
                decimal.Decimal("0.10000000000000001"),
                decimal.Decimal("0.1"),
            )
        )

    def test_json_stream_does_not_split_unicode_line_separators(self) -> None:
        output = '"before\u0085after"\n"before\u2028after"\n'.encode()
        result = JQ_COMPAT.ProcessResult(
            argv=[],
            returncode=0,
            signal=None,
            timed_out=False,
            duration_ms=0,
            stdout_b64=base64.b64encode(output).decode("ascii"),
            stderr_b64="",
            stdout_text=output.decode(),
            stderr_text="",
        )
        values, error = JQ_COMPAT.json_stream(result)
        self.assertIsNone(error)
        self.assertEqual(values, ["before\u0085after", "before\u2028after"])

    def test_json_stream_preserves_decimal_precision(self) -> None:
        output = b"0.10000000000000001\n"
        result = JQ_COMPAT.ProcessResult(
            argv=[],
            returncode=0,
            signal=None,
            timed_out=False,
            duration_ms=0,
            stdout_b64=base64.b64encode(output).decode("ascii"),
            stderr_b64="",
            stdout_text=output.decode(),
            stderr_text="",
        )
        values, error = JQ_COMPAT.json_stream(result)
        self.assertIsNone(error)
        self.assertEqual(values, [decimal.Decimal("0.10000000000000001")])
        self.assertFalse(
            JQ_COMPAT.semantic_equal(values, [decimal.Decimal("0.1")])
        )

    def test_json_stream_rejects_duplicate_object_members(self) -> None:
        output = b'{"a":1,"a":2}\n'
        result = JQ_COMPAT.ProcessResult(
            argv=[],
            returncode=0,
            signal=None,
            timed_out=False,
            duration_ms=0,
            stdout_b64=base64.b64encode(output).decode("ascii"),
            stderr_b64="",
            stdout_text=output.decode(),
            stderr_text="",
        )
        values, error = JQ_COMPAT.json_stream(result)
        self.assertIsNone(values)
        self.assertIn("duplicate object member 'a'", error)


class RunnerTests(unittest.TestCase):
    def make_cli(
        self,
        directory: pathlib.Path,
        name: str,
        mode: str = "pass",
        version: str = "jq-1.8.1",
        target: pathlib.Path | None = None,
    ) -> pathlib.Path:
        path = directory / name
        path.write_text(
            FAKE_CLI.format(
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
        candidate_mode: str,
        *,
        candidate_version: str = "jq-odin-test",
        timeout: float = 5.0,
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, object]]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = pathlib.Path(temporary.name)
        suite = directory / "sample.test"
        suite.write_text(SUITE, encoding="utf-8")
        skips = directory / "skips.json"
        skips.write_text("{}\n", encoding="utf-8")
        oracle = self.make_cli(directory, "oracle")
        candidate = self.make_cli(
            directory,
            "candidate",
            mode=candidate_mode,
            version=candidate_version,
            target=oracle if candidate_mode == "clobber_version" else None,
        )
        report = directory / "report.json"

        completed = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--oracle",
                str(oracle),
                "--candidate",
                str(candidate),
                "--tests",
                str(suite),
                "--skips",
                str(skips),
                "--json-report",
                str(report),
                "--timeout",
                str(timeout),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        parsed_report = (
            json.loads(report.read_text(encoding="utf-8"))
            if report.exists()
            else {}
        )
        return completed, parsed_report

    def test_identical_behavior_passes_all_cases(self) -> None:
        completed, report = self.run_harness("pass")
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(
            report["summary"],
            {
                "selected": 5,
                "passed": 5,
                "failed": 0,
                "skipped": 0,
                "errors": 0,
            },
        )

    def test_reordered_outputs_fail_with_case_evidence(self) -> None:
        completed, report = self.run_harness("reverse")
        self.assertEqual(completed.returncode, 1)
        self.assertIn("output 1 differs", completed.stdout)
        statuses = {
            case["case"]["program"]: case["status"]
            for case in report["cases"]
        }
        self.assertEqual(statuses[".two"], "fail")

    def test_missing_output_is_counted(self) -> None:
        completed, _ = self.run_harness("omit")
        self.assertEqual(completed.returncode, 1)
        self.assertIn("output count differs: oracle=2, candidate=1", completed.stdout)

    def test_diagnostic_difference_respects_ignore_marker(self) -> None:
        completed, report = self.run_harness("diagnostic")
        self.assertEqual(completed.returncode, 1)
        cases = {
            case["case"]["program"]: case
            for case in report["cases"]
        }
        self.assertEqual(cases["compile_fail"]["status"], "fail")
        self.assertEqual(cases["compile_fail_ignored"]["status"], "pass")

    def test_unpinned_oracle_is_rejected(self) -> None:
        completed, _ = self.run_harness("pass", candidate_version="jq-odin-test")
        self.assertNotIn("HARNESS ERROR", completed.stderr)

        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            suite = directory / "sample.test"
            suite.write_text(SUITE, encoding="utf-8")
            skips = directory / "skips.json"
            skips.write_text("{}\n", encoding="utf-8")
            oracle = self.make_cli(directory, "oracle", version="jq-1.7")
            candidate = self.make_cli(directory, "candidate")
            rejected = subprocess.run(
                [
                    sys.executable,
                    str(RUNNER),
                    "--oracle",
                    str(oracle),
                    "--candidate",
                    str(candidate),
                    "--tests",
                    str(suite),
                    "--skips",
                    str(skips),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
        self.assertEqual(rejected.returncode, 2)
        self.assertIn("expected 'jq-1.8.1'", rejected.stderr)

    def test_candidate_cannot_replace_captured_oracle(self) -> None:
        completed, report = self.run_harness("clobber_version")
        self.assertEqual(completed.returncode, 1)
        cases = {
            case["case"]["program"]: case
            for case in report["cases"]
        }
        self.assertEqual(cases["."]["status"], "fail")

    def test_timeout_terminates_candidate_descendants(self) -> None:
        started = time.monotonic()
        completed, report = self.run_harness("hang_descendant", timeout=0.2)
        elapsed = time.monotonic() - started
        self.assertEqual(completed.returncode, 1)
        self.assertLess(elapsed, 3)
        first = next(
            case for case in report["cases"]
            if case["case"]["kind"] == "execute"
        )
        self.assertTrue(first["candidate"]["timed_out"])

    def test_process_environment_does_not_inherit_secrets(self) -> None:
        with mock.patch.dict(
            JQ_COMPAT.os.environ,
            {"JQ_COMPAT_TEST_SECRET": "must-not-leak"},
        ):
            result = JQ_COMPAT.run_process(
                ["/usr/bin/env"],
                b"",
                ROOT,
                2,
            )
        self.assertNotIn("JQ_COMPAT_TEST_SECRET", result.stdout_text)

    def test_oracle_version_requires_clean_success(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            for mode in ("bad_version_status", "bad_version_shape"):
                oracle = self.make_cli(
                    directory,
                    mode,
                    mode=mode,
                )
                with self.assertRaises(JQ_COMPAT.HarnessError):
                    JQ_COMPAT.version_of(
                        oracle,
                        2,
                        ROOT,
                        require_clean=True,
                    )


if __name__ == "__main__":
    unittest.main()
