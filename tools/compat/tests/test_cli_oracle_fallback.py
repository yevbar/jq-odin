#!/usr/bin/env python3
"""Focused tests for the standalone jq-oracle authentication fallback."""

from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
CLI_TEST = ROOT / "cmd/jq-odin/test_cli.py"
SPEC = importlib.util.spec_from_file_location("jq_odin_test_cli", CLI_TEST)
assert SPEC is not None and SPEC.loader is not None
CLI = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CLI
SPEC.loader.exec_module(CLI)


class OracleFallbackTests(unittest.TestCase):
    def test_matching_digest_is_required_and_returned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            oracle = pathlib.Path(directory) / "jq"
            oracle.write_bytes(b"trusted jq oracle\n")
            digest = hashlib.sha256(oracle.read_bytes()).hexdigest()

            resolved, actual = CLI.authenticate_oracle(oracle, digest, None)

            self.assertEqual(resolved, oracle.resolve())
            self.assertEqual(actual, digest)

    def test_mismatching_digest_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            oracle = pathlib.Path(directory) / "jq"
            oracle.write_bytes(b"substituted jq oracle\n")
            trusted = hashlib.sha256(b"different oracle\n").hexdigest()

            with self.assertRaisesRegex(CLI.OracleAuthError, "SHA-256 mismatch"):
                CLI.authenticate_oracle(oracle, trusted, None)


if __name__ == "__main__":
    unittest.main()
