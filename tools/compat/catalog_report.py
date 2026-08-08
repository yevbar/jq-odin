#!/usr/bin/env python3
"""Summarize a jq_compat JSON report without changing its observations."""

from __future__ import annotations

import argparse
import base64
import binascii
import decimal
import json
import math
import pathlib
import sys
from collections import defaultdict
from typing import Any


SCHEMA_VERSION = 1
OWNERS = {
    "harness-error": "compat",
    "skip": "compat",
    "timeout": "value/eval",
    "status": "cli",
    "signal": "cli",
    "output-cardinality": "value/eval",
    "output-order": "value/eval",
    "output-value": "value/eval",
    "malformed-output": "cli",
    "stdout": "cli",
    "stderr": "diagnostic/cli",
    "compile-status": "program/compiler",
    "unknown": "compat",
    "compile-diagnostic": "syntax/diagnostic",
    "compile-stdout": "cli",
    "pass": "none",
}

_CASE_FIELDS = {
    "case_id": str,
    "source": str,
    "line": int,
    "ordinal": int,
    "kind": str,
    "program": str,
}
_STATUSES = {"pass", "fail", "error", "skip"}
_PROCESS_FIELDS = (
    "argv",
    "returncode",
    "signal",
    "timed_out",
    "duration_ms",
    "stdout_b64",
    "stderr_b64",
    "stdout_text",
    "stderr_text",
)


def _json_values_equal(left: Any, right: Any) -> bool:
    """Compare parsed JSON values using jq_compat's semantic rules."""
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
    if left_is_number or right_is_number:
        return left_is_number and right_is_number and left == right
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is type(right) and left == right
    if type(left) is not type(right):
        return False
    if isinstance(left, list):
        return len(left) == len(right) and all(
            _json_values_equal(a, b) for a, b in zip(left, right)
        )
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(
            _json_values_equal(left[key], right[key]) for key in left
        )
    return left == right


def _same_unordered_values(left: list[Any], right: list[Any]) -> bool:
    """Check output multisets without treating JSON true/false as numbers."""
    if len(left) != len(right):
        return False
    unmatched = list(right)
    for value in left:
        for index, candidate in enumerate(unmatched):
            if _json_values_equal(value, candidate):
                del unmatched[index]
                break
        else:
            return False
    return True


def _stdout_records(stdout_b64: str) -> list[str]:
    """Split process output on the LF record delimiter used by jq_compat."""
    try:
        text = base64.b64decode(stdout_b64, validate=True).decode()
    except (binascii.Error, UnicodeError) as exc:
        raise ValueError("stdout_b64 is not valid Base64 UTF-8") from exc
    if text == "":
        return []
    if not text.endswith("\n"):
        raise ValueError("stdout does not end with a newline")
    return text[:-1].split("\n")


def _ordered_output_difference(case_record: dict[str, Any]) -> str:
    """Distinguish a pure reorder from a changed JSON value when available."""
    oracle = case_record.get("oracle", {})
    candidate = case_record.get("candidate", {})
    try:
        oracle_values = [
            json.loads(
                line,
                parse_float=decimal.Decimal,
                parse_constant=decimal.Decimal,
            )
            for line in _stdout_records(oracle["stdout_b64"])
        ]
        candidate_values = [
            json.loads(
                line,
                parse_float=decimal.Decimal,
                parse_constant=decimal.Decimal,
            )
            for line in _stdout_records(candidate["stdout_b64"])
        ]
    except (KeyError, TypeError, ValueError, UnicodeError, json.JSONDecodeError):
        return "output-value"
    if len(oracle_values) == len(candidate_values) and all(
        _json_values_equal(oracle, candidate)
        for oracle, candidate in zip(oracle_values, candidate_values)
    ):
        return "output-value"
    if _same_unordered_values(oracle_values, candidate_values):
        return "output-order"
    return "output-value"


def categories(case_record: dict[str, Any]) -> list[str]:
    """Return stable, non-lossy labels for one report case."""
    if case_record.get("status") == "skip":
        return ["skip"]
    if case_record.get("status") == "error":
        return ["harness-error"]
    differences = case_record.get("differences", [])
    labels: list[str] = []
    for difference in differences:
        if difference == "candidate timed out":
            labels.append("timeout")
        elif difference.startswith("exit status differs:"):
            labels.append("status")
        elif difference.startswith("signal differs:"):
            labels.append("signal")
        elif difference.startswith("output count differs:"):
            labels.append("output-cardinality")
        elif difference.startswith("output ") and " differs:" in difference:
            labels.append(_ordered_output_difference(case_record))
        elif difference == "stderr bytes differ":
            labels.append("stderr")
        elif difference == "compile diagnostic bytes differ":
            labels.append("compile-diagnostic")
        elif difference == "compile-failure stdout bytes differ":
            labels.append("compile-stdout")
        elif difference.startswith(
            (
                "oracle compiled a fixture marked %%FAIL",
                "candidate compiled a fixture marked %%FAIL",
            )
        ):
            labels.append("compile-status")
        elif difference == "stdout bytes differ":
            labels.append("stdout")
        elif difference.startswith(
            (
                "stdout is not UTF-8:",
                "stdout does not end with a newline",
                "stdout contains an empty line",
                "stdout output ",
            )
        ):
            labels.append("malformed-output")
        elif difference.startswith("oracle harness error:") or difference.startswith(
            "oracle timed out"
        ):
            labels.append("harness-error")
        else:
            labels.append("unknown")
    return list(dict.fromkeys(labels or ["pass"]))


def load_report(path: pathlib.Path) -> dict[str, Any]:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read report {path}: {exc}") from exc
    if not isinstance(report, dict) or not isinstance(report.get("cases"), list):
        raise ValueError("report must contain a cases array")
    if type(report.get("schema_version")) is not int or report.get(
        "schema_version"
    ) != SCHEMA_VERSION:
        raise ValueError(
            f"unsupported report schema {report.get('schema_version')!r}; "
            f"expected {SCHEMA_VERSION}"
        )
    _validate_cases(report["cases"])
    return report


def _validate_cases(cases: list[Any]) -> None:
    """Reject malformed producer records before classification can normalize them."""
    for index, item in enumerate(cases):
        prefix = f"cases[{index}]"
        if not isinstance(item, dict):
            raise ValueError(f"{prefix} must be an object")

        case = item.get("case")
        if not isinstance(case, dict):
            raise ValueError(f"{prefix}.case must be an object")
        for field, expected_type in _CASE_FIELDS.items():
            value = case.get(field)
            if field not in case or type(value) is not expected_type:
                raise ValueError(
                    f"{prefix}.case.{field} must be a {expected_type.__name__}"
                )

        status = item.get("status")
        if type(status) is not str or status not in _STATUSES:
            raise ValueError(f"{prefix}.status must be one of {sorted(_STATUSES)!r}")

        if "differences" not in item:
            if status != "skip":
                raise ValueError(f"{prefix}.differences is required")
            continue
        differences = item["differences"]
        if not isinstance(differences, list) or any(
            type(difference) is not str for difference in differences
        ):
            raise ValueError(f"{prefix}.differences must be an array of strings")
        if status == "fail" and not differences:
            raise ValueError(f"{prefix}.differences must describe a failed case")

        if status == "skip":
            continue
        for result_name in ("oracle", "candidate"):
            _validate_process_result(item.get(result_name), f"{prefix}.{result_name}")


def _validate_process_result(value: Any, prefix: str) -> None:
    """Validate the captured process record before any field can be classified."""
    if not isinstance(value, dict):
        raise ValueError(f"{prefix} must be an object")
    for field in _PROCESS_FIELDS:
        if field not in value:
            raise ValueError(f"{prefix}.{field} is required")

    if not isinstance(value["argv"], list) or any(
        type(argument) is not str for argument in value["argv"]
    ):
        raise ValueError(f"{prefix}.argv must be an array of strings")
    for field in ("returncode", "signal"):
        if value[field] is not None and type(value[field]) is not int:
            raise ValueError(f"{prefix}.{field} must be an integer or null")
    if type(value["timed_out"]) is not bool:
        raise ValueError(f"{prefix}.timed_out must be a boolean")
    if type(value["duration_ms"]) is not int or value["duration_ms"] < 0:
        raise ValueError(f"{prefix}.duration_ms must be a non-negative integer")
    for field in ("stdout_b64", "stderr_b64"):
        encoded = value[field]
        if type(encoded) is not str:
            raise ValueError(f"{prefix}.{field} must be a Base64 string")
        try:
            base64.b64decode(encoded, validate=True)
        except (binascii.Error, UnicodeEncodeError) as exc:
            raise ValueError(f"{prefix}.{field} must be valid Base64") from exc
    for field in ("stdout_text", "stderr_text"):
        if type(value[field]) is not str:
            raise ValueError(f"{prefix}.{field} must be a string")


def taxonomy(report: dict[str, Any], source: str) -> dict[str, Any]:
    if not isinstance(report, dict) or not isinstance(report.get("cases"), list):
        raise ValueError("report must contain a cases array")
    if type(report.get("schema_version")) is not int or report.get(
        "schema_version"
    ) != SCHEMA_VERSION:
        raise ValueError(
            f"unsupported report schema {report.get('schema_version')!r}; "
            f"expected {SCHEMA_VERSION}"
        )
    _validate_cases(report["cases"])
    clusters: dict[str, list[dict[str, Any]]] = defaultdict(list)
    case_rows: list[dict[str, Any]] = []
    for item in report["cases"]:
        if not isinstance(item, dict) or not isinstance(item.get("case"), dict):
            raise ValueError("each report case must contain a case object")
        case = item["case"]
        labels = categories(item)
        row = {
            "case_id": case.get("case_id"),
            "source": case.get("source"),
            "line": case.get("line"),
            "ordinal": case.get("ordinal"),
            "kind": case.get("kind"),
            "program": case.get("program"),
            "status": item.get("status"),
            "categories": labels,
            "differences": item.get("differences", []),
        }
        case_rows.append(row)
        for label in labels:
            clusters[label].append(row)

    cluster_rows = []
    for label, rows in clusters.items():
        cluster_rows.append(
            {
                "cluster": label,
                "cases": len(rows),
                "owner": OWNERS.get(label, "compat"),
                "case_ids": [row["case_id"] for row in rows],
            }
        )
    cluster_rows.sort(key=lambda row: (-row["cases"], row["cluster"]))
    return {
        "schema_version": SCHEMA_VERSION,
        "source_report": source,
        "suite": report.get("suite"),
        "oracle": report.get("oracle"),
        "candidate": report.get("candidate"),
        "selection": report.get("selection"),
        "summary": {
            "cases": len(case_rows),
            "by_status": {
                status: sum(row["status"] == status for row in case_rows)
                for status in sorted({row["status"] for row in case_rows})
            },
            "cluster_case_total": sum(row["cases"] for row in cluster_rows),
        },
        "clusters": cluster_rows,
        "cases": case_rows,
    }


def _encoded_taxonomy(result: dict[str, Any]) -> bytes:
    """Serialize schema-valid strings without failing on escaped surrogates."""
    encoded = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    return encoded.encode("utf-8", errors="backslashreplace")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Create a reproducible failure taxonomy from jq_compat JSON."
    )
    parser.add_argument("report", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        report = load_report(args.report)
        result = taxonomy(report, args.report.name)
        encoded = _encoded_taxonomy(result)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(encoded)
        else:
            sys.stdout.buffer.write(encoded)
            sys.stdout.buffer.flush()
        print(
            "SUMMARY "
            + " ".join(
                f"{key}={value}" for key, value in result["summary"]["by_status"].items()
            ),
            file=sys.stderr,
        )
        return 0
    except ValueError as exc:
        parser.error(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
