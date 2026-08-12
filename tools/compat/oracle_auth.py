#!/usr/bin/env python3
"""Authenticate a jq oracle as trusted, regular, executable, distinct bytes."""

from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import stat
import sys


class OracleAuthError(Exception):
    pass


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise OracleAuthError(f"cannot hash executable {path}: {exc}") from exc
    return digest.hexdigest()


def parse_trusted_sha256(value: str) -> str:
    digest = value.strip().lower()
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise OracleAuthError("trusted oracle SHA-256 must be exactly 64 hex digits")
    return digest


def regular_executable(path: pathlib.Path, role: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as exc:
        raise OracleAuthError(f"cannot inspect {role} executable {path}: {exc}") from exc
    if stat.S_ISLNK(metadata.st_mode):
        raise OracleAuthError(f"{role} executable must not be a symlink: {path}")
    if not stat.S_ISREG(metadata.st_mode):
        raise OracleAuthError(f"{role} executable must be a regular file: {path}")
    if not os.access(path, os.X_OK):
        raise OracleAuthError(f"{role} executable is not executable: {path}")


def authenticate_oracle(
    oracle: pathlib.Path,
    trusted_sha256: str,
    candidate: pathlib.Path | None = None,
) -> tuple[pathlib.Path, str]:
    regular_executable(oracle, "oracle")
    trusted = parse_trusted_sha256(trusted_sha256)
    actual = sha256_file(oracle)
    if actual != trusted:
        raise OracleAuthError(
            f"oracle SHA-256 mismatch: trusted {trusted}, actual {actual}"
        )

    if candidate is not None:
        try:
            if os.path.samefile(oracle, candidate):
                raise OracleAuthError("oracle and candidate are the same file")
        except FileNotFoundError as exc:
            raise OracleAuthError(f"candidate executable is missing: {candidate}") from exc
        candidate_sha256 = sha256_file(candidate)
        if candidate_sha256 == actual:
            raise OracleAuthError("oracle and candidate executable bytes are identical")
    return oracle.resolve(strict=True), actual


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    digest_parser = subparsers.add_parser("digest")
    digest_parser.add_argument("path", type=pathlib.Path)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--oracle", required=True, type=pathlib.Path)
    verify_parser.add_argument("--trusted-sha256", required=True)
    verify_parser.add_argument("--candidate", type=pathlib.Path)
    args = parser.parse_args(argv)

    try:
        if args.command == "digest":
            print(sha256_file(args.path))
        else:
            _, actual = authenticate_oracle(
                args.oracle, args.trusted_sha256, args.candidate
            )
            print(actual)
    except OracleAuthError as exc:
        print(f"oracle authentication error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
