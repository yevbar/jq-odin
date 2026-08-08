from __future__ import annotations

import importlib.util
import base64
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
RUNNER = ROOT / "tools/compat/catalog_report.py"
SPEC = importlib.util.spec_from_file_location("catalog_report", RUNNER)
assert SPEC is not None and SPEC.loader is not None
REPORT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REPORT
SPEC.loader.exec_module(REPORT)


def process_result() -> dict[str, object]:
    return {
        "argv": ["jq"],
        "returncode": 0,
        "signal": None,
        "timed_out": False,
        "duration_ms": 1,
        "stdout_b64": base64.b64encode(b"1\n").decode(),
        "stderr_b64": "",
        "stdout_text": "1\n",
        "stderr_text": "",
    }


def report_with_lone_surrogate() -> dict[str, object]:
    item = case(1, "fail", ["stderr bytes differ"])
    item["oracle"]["stderr_text"] = "diagnostic \ud800"
    item["candidate"]["stderr_text"] = "diagnostic \ud800"
    return {
        "schema_version": 1,
        "suite": "suite \ud800",
        "cases": [item],
    }


def case(ordinal: int, status: str, differences: list[str]) -> dict[str, object]:
    item: dict[str, object] = {
        "case": {
            "case_id": f"upstream/jq/tests/jq.test:{ordinal}",
            "source": "upstream/jq/tests/jq.test",
            "line": ordinal,
            "ordinal": ordinal,
            "kind": "execute",
            "program": ".",
        },
        "status": status,
        "differences": differences,
    }
    if status != "skip":
        item["oracle"] = process_result()
        item["candidate"] = process_result()
    return item


def with_outputs(item: dict[str, object], oracle: list[str], candidate: list[str]) -> dict[str, object]:
    item["oracle"]["stdout_b64"] = base64.b64encode(
        "\n".join(oracle).encode() + b"\n"
    ).decode()
    item["candidate"]["stdout_b64"] = base64.b64encode(
        "\n".join(candidate).encode() + b"\n"
    ).decode()
    return item


class CatalogReportTests(unittest.TestCase):
    def test_taxonomy_reproduction_gates_catalog_on_runner_status(self) -> None:
        document = (ROOT / "compat/failure-taxonomy.md").read_text(encoding="utf-8")
        self.assertIn('REPORT=build/compat/jq-522.json\nrm -f "$REPORT"', document)
        self.assertIn('harness_status=$?\nfi\ncase "$harness_status" in\n  0|1)', document)
        self.assertIn('tools/compat/catalog_report.py \\\n  "$REPORT"', document)
        self.assertNotIn('|| test $? -eq 1', document)

    def test_load_report_rejects_non_integer_schema_versions(self) -> None:
        valid = {"schema_version": 1, "cases": []}
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "report.json"
            path.write_text(json.dumps(valid), encoding="utf-8")
            self.assertEqual(REPORT.load_report(path)["schema_version"], 1)
            for version in (True, False, 1.0, 1.00):
                invalid = {**valid, "schema_version": version}
                path.write_text(json.dumps(invalid), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "unsupported report schema"):
                    REPORT.load_report(path)

    def test_load_report_rejects_missing_or_invalid_case_status(self) -> None:
        valid = {"schema_version": 1, "cases": [case(1, "pass", [])]}
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "report.json"
            for mutation in (
                lambda item: item.pop("status"),
                lambda item: item.__setitem__("status", "unknown"),
                lambda item: item.__setitem__("status", True),
            ):
                invalid = json.loads(json.dumps(valid))
                mutation(invalid["cases"][0])
                path.write_text(json.dumps(invalid), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, r"cases\[0\]\.status"):
                    REPORT.load_report(path)

    def test_load_report_rejects_malformed_case_fields(self) -> None:
        valid = {"schema_version": 1, "cases": [case(1, "pass", [])]}
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "report.json"
            for field, value in (("case_id", None), ("line", True), ("program", 1)):
                invalid = json.loads(json.dumps(valid))
                if value is None:
                    invalid["cases"][0]["case"].pop(field)
                else:
                    invalid["cases"][0]["case"][field] = value
                path.write_text(json.dumps(invalid), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, rf"cases\[0\]\.case\.{field}"):
                    REPORT.load_report(path)

    def test_load_report_rejects_missing_or_malformed_differences(self) -> None:
        valid = {"schema_version": 1, "cases": [case(1, "fail", ["stderr bytes differ"])]}
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "report.json"
            for differences in (None, "stderr bytes differ", ["ok", 1], [True]):
                invalid = json.loads(json.dumps(valid))
                if differences is None:
                    invalid["cases"][0].pop("differences")
                else:
                    invalid["cases"][0]["differences"] = differences
                path.write_text(json.dumps(invalid), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, r"cases\[0\]\.differences"):
                    REPORT.load_report(path)

    def test_load_report_rejects_partial_failed_case_without_differences(self) -> None:
        report = {"schema_version": 1, "cases": [case(1, "fail", [])]}
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "report.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError,
                r"cases\[0\]\.differences must describe a failed case",
            ):
                REPORT.load_report(path)

    def test_load_report_rejects_malformed_process_stdout_base64(self) -> None:
        valid = case(1, "fail", ["stdout bytes differ"])
        valid["oracle"] = process_result()
        valid["candidate"] = process_result()
        valid["candidate"]["stdout_b64"] = "not-base64"
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "report.json"
            path.write_text(
                json.dumps({"schema_version": 1, "cases": [valid]}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, r"cases\[0\]\.candidate\.stdout_b64"):
                REPORT.load_report(path)

    def test_load_report_rejects_malformed_required_process_fields(self) -> None:
        for field, value in (("oracle", None), ("candidate", {"argv": "jq"})):
            with self.subTest(field=field):
                item = case(1, "fail", ["stdout bytes differ"])
                item["oracle"] = process_result()
                item["candidate"] = process_result()
                item[field] = value
                with tempfile.TemporaryDirectory() as directory:
                    path = pathlib.Path(directory) / "report.json"
                    path.write_text(
                        json.dumps({"schema_version": 1, "cases": [item]}),
                        encoding="utf-8",
                    )
                    with self.assertRaisesRegex(ValueError, rf"cases\[0\]\.{field}"):
                        REPORT.load_report(path)

    def test_machine_readable_owners_match_taxonomy_document(self) -> None:
        self.assertEqual(REPORT.OWNERS["timeout"], "value/eval")
        self.assertEqual(REPORT.OWNERS["output-cardinality"], "value/eval")
        self.assertEqual(REPORT.OWNERS["output-order"], "value/eval")
        self.assertEqual(REPORT.OWNERS["unknown"], "compat")
        self.assertEqual(REPORT.OWNERS["compile-diagnostic"], "syntax/diagnostic")
        self.assertEqual(REPORT.OWNERS["compile-stdout"], "cli")

    def test_explicit_categories_do_not_use_output_order_fallback(self) -> None:
        differences = [
            "oracle compiled a fixture marked %%FAIL",
            "candidate compiled a fixture marked %%FAIL",
            "stdout is not UTF-8: byte 0",
            "stdout does not end with a newline",
            "stdout output 1 is not JSON: bad",
        ]
        labels = REPORT.categories(case(1, "fail", differences))
        self.assertEqual(
            labels,
            ["compile-status", "malformed-output"],
        )
        self.assertNotIn("output-order", labels)

    def test_unrecognized_difference_fails_closed(self) -> None:
        self.assertEqual(
            REPORT.categories(case(1, "fail", ["new difference"])),
            ["unknown"],
        )

    def test_order_comparison_does_not_equate_boolean_and_number(self) -> None:
        item = with_outputs(
            case(1, "fail", ["output 1 differs: oracle=True, candidate=1"]),
            ["true"],
            ["1"],
        )
        self.assertEqual(REPORT.categories(item), ["output-value"])

    def test_order_comparison_preserves_decimal_semantics(self) -> None:
        cases = (
            ("0.1", "0.10000000000000001"),
            ("1.234567890123456789", "1.234567890123456788"),
            ("1e400", "1e401"),
        )
        for oracle, candidate in cases:
            with self.subTest(oracle=oracle, candidate=candidate):
                item = with_outputs(
                    case(1, "fail", ["output 1 differs: oracle=x, candidate=y"]),
                    [oracle],
                    [candidate],
                )
                self.assertEqual(REPORT.categories(item), ["output-value"])

    def test_order_comparison_requires_an_actual_reorder(self) -> None:
        identical = with_outputs(
            case(1, "fail", ["output 1 differs: oracle=NaN, candidate=NaN"]),
            ["NaN"],
            ["NaN"],
        )
        self.assertEqual(REPORT.categories(identical), ["output-value"])

        reordered = with_outputs(
            case(2, "fail", ["output 1 differs: oracle=x, candidate=y"]),
            ["1", "2"],
            ["2", "1"],
        )
        self.assertEqual(REPORT.categories(reordered), ["output-order"])

    def test_order_comparison_uses_only_lf_as_record_delimiter(self) -> None:
        value = '"before\u0085middle\u2028after\u2029"'
        item = with_outputs(
            case(1, "fail", ["output 1 differs: oracle=x, candidate=y"]),
            [value, "0"],
            ["0", value],
        )
        self.assertEqual(REPORT.categories(item), ["output-order"])

    def test_taxonomy_preserves_case_evidence_and_overlapping_clusters(self) -> None:
        report = {
            "schema_version": 1,
            "suite": "upstream/jq/tests/jq.test",
            "oracle": {"version": "jq-1.8.1", "sha256": "oracle"},
            "candidate": {"version": "odin-test"},
            "selection": {"shard_count": 1, "shard_index": 0},
            "cases": [
                case(8, "pass", []),
                case(9, "fail", ["exit status differs: oracle=0, candidate=3", "stderr bytes differ"]),
                with_outputs(case(10, "fail", ["output 1 differs: oracle=1, candidate=2"]), ["1", "2"], ["2", "1"]),
                case(11, "skip", []),
            ],
        }
        result = REPORT.taxonomy(report, "report.json")
        self.assertEqual(result["summary"]["cases"], 4)
        self.assertEqual(result["summary"]["cluster_case_total"], 5)
        clusters = {row["cluster"]: row for row in result["clusters"]}
        self.assertEqual(clusters["status"]["owner"], "cli")
        self.assertEqual(clusters["stderr"]["case_ids"], ["upstream/jq/tests/jq.test:9"])
        self.assertEqual(clusters["skip"]["cases"], 1)
        self.assertEqual(clusters["output-order"]["cases"], 1)
        self.assertEqual(result["cases"][1]["line"], 9)

    def test_cli_writes_deterministic_json_and_summary(self) -> None:
        report = {
            "schema_version": 1,
            "cases": [case(8, "pass", [])],
        }
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "report.json"
            output = pathlib.Path(directory) / "taxonomy.json"
            source.write_text(json.dumps(report), encoding="utf-8")
            self.assertEqual(REPORT.main([str(source), "--output", str(output)]), 0)
            parsed = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(parsed["clusters"][0]["cluster"], "pass")

    def test_cli_output_preserves_lone_surrogates_without_truncating_file(self) -> None:
        report = report_with_lone_surrogate()
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "report.json"
            output = pathlib.Path(directory) / "taxonomy.json"
            source.write_text(json.dumps(report), encoding="utf-8")
            output.write_bytes(b"previous complete report\n")

            self.assertEqual(REPORT.main([str(source), "--output", str(output)]), 0)

            payload = output.read_bytes()
            self.assertIn(b'"suite": "suite \\ud800"', payload)
            self.assertEqual(json.loads(payload)["suite"], "suite \ud800")

    def test_cli_stdout_preserves_lone_surrogates(self) -> None:
        report = report_with_lone_surrogate()
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "report.json"
            source.write_text(json.dumps(report), encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(RUNNER), str(source)],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

        self.assertEqual(completed.returncode, 0)
        self.assertIn(b'"suite": "suite \\ud800"', completed.stdout)
        self.assertIn(b"SUMMARY fail=1", completed.stderr)

    def test_cli_output_is_location_independent(self) -> None:
        report = {
            "schema_version": 1,
            "cases": [case(8, "pass", [])],
        }
        with tempfile.TemporaryDirectory() as left, tempfile.TemporaryDirectory() as right:
            outputs = []
            for directory in (left, right):
                source = pathlib.Path(directory) / "report.json"
                output = pathlib.Path(directory) / "taxonomy.json"
                source.write_text(json.dumps(report), encoding="utf-8")
                previous = os.getcwd()
                try:
                    os.chdir(directory)
                    self.assertEqual(REPORT.main(["report.json", "--output", "taxonomy.json"]), 0)
                finally:
                    os.chdir(previous)
                outputs.append(output.read_bytes())
            self.assertEqual(outputs[0], outputs[1])


if __name__ == "__main__":
    unittest.main()
