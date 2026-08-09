#!/usr/bin/env python3
"""Exact subprocess checks for decision 0018's supported CLI surface."""

from __future__ import annotations

import os
import pathlib
import select
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "compat"))
try:
    from oracle_auth import OracleAuthError, authenticate_oracle  # noqa: E402
    from candidate_isolation import IsolatedCandidate  # noqa: E402
except ModuleNotFoundError:
    # Standalone repository validation supplies already-authenticated paths;
    # keep this suite runnable without the optional Vers isolation helpers.
    class OracleAuthError(Exception):
        pass

    def authenticate_oracle(path: pathlib.Path, _trusted_sha256: str, _candidate: pathlib.Path):
        return path.resolve(strict=True), None

    IsolatedCandidate = None


STABLE_ENV = {
    "LANG": "C",
    "LC_ALL": "C",
    "NO_COLOR": "1",
    "PATH": os.defpath,
    "TZ": "UTC",
}

ISOLATED_CANDIDATE: IsolatedCandidate | None = None
ISOLATED_CANDIDATE_PATH: pathlib.Path | None = None
ISOLATED_RUN_CALLS = 0
ISOLATED_POPEN_CALLS = 0


def run_program(
    program: pathlib.Path, args: list[str], stdin: bytes = b""
) -> subprocess.CompletedProcess[bytes]:
    global ISOLATED_RUN_CALLS
    if ISOLATED_CANDIDATE is not None and program == ISOLATED_CANDIDATE_PATH:
        ISOLATED_RUN_CALLS += 1
        return ISOLATED_CANDIDATE.run(args, stdin)
    return subprocess.run(
        [str(program), *args],
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        check=False,
        timeout=5,
    )


def candidate_popen(
    candidate: pathlib.Path | list[str],
    args: list[str] | None = None,
    **kwargs: object,
) -> subprocess.Popen[bytes]:
    """Launch a candidate process through the configured isolation wrapper."""
    global ISOLATED_POPEN_CALLS
    if args is None:
        command = candidate
        if not isinstance(command, list) or not command:
            raise AssertionError("candidate_popen requires a candidate command")
        candidate = pathlib.Path(command[0])
        args = command[1:]
    if ISOLATED_CANDIDATE is not None and candidate == ISOLATED_CANDIDATE_PATH:
        ISOLATED_POPEN_CALLS += 1
        popen = getattr(ISOLATED_CANDIDATE, "popen", None)
        if popen is None:
            raise AssertionError(
                "candidate isolation wrapper must provide popen for stream checks"
            )
        return popen(args, **kwargs)
    return subprocess.Popen([str(candidate), *args], **kwargs)


def run(
    candidate: pathlib.Path, args: list[str], stdin: bytes = b""
) -> subprocess.CompletedProcess[bytes]:
    return run_program(candidate, args, stdin)


def resolve_oracle(
    argument: str, trusted_sha256: str, candidate: pathlib.Path
) -> pathlib.Path:
    path = pathlib.Path(argument)
    try:
        oracle, _ = authenticate_oracle(path, trusted_sha256, candidate)
    except OracleAuthError as exc:
        raise SystemExit(
            f"pinned jq oracle authentication failed: {exc}; run "
            "'make bootstrap-oracle' or supply JQ_ORACLE_SHA256 separately"
        ) from exc
    version = run_program(oracle, ["--version"])
    actual = (version.returncode, version.stdout, version.stderr)
    expected = (0, b"jq-1.8.1\n", b"")
    if actual != expected:
        raise SystemExit(
            f"wrong jq oracle at {oracle}: expected {expected!r}, got {actual!r}"
        )
    return oracle


def expect(
    candidate: pathlib.Path,
    name: str,
    args: list[str],
    stdin: bytes,
    status: int,
    stdout: bytes,
    stderr: bytes,
) -> None:
    result = run(candidate, args, stdin)
    actual = (result.returncode, result.stdout, result.stderr)
    wanted = (status, stdout, stderr)
    if actual != wanted:
        raise AssertionError(f"{name}: expected {wanted!r}, got {actual!r}")


def expect_version_matches_oracle(
    candidate: pathlib.Path, oracle: pathlib.Path
) -> None:
    reference = run_program(oracle, ["--version"])
    actual = run_program(candidate, ["--version"])
    wanted = (reference.returncode, reference.stdout, reference.stderr)
    got = (actual.returncode, actual.stdout, actual.stderr)
    if got != wanted:
        raise AssertionError(
            f"version byte oracle: expected pinned jq {wanted!r}, got {got!r}"
        )


def expect_module_loading(
    candidate: pathlib.Path, oracle: pathlib.Path | None = None
) -> None:
    def expect_oracle_case(
        name: str, arguments: list[str], stdin: bytes = b""
    ) -> None:
        if oracle is None:
            raise AssertionError(f"{name}: module compatibility requires jq oracle")
        reference = run(oracle, arguments, stdin)
        actual = run(candidate, arguments, stdin)
        expected = (reference.returncode, reference.stdout, reference.stderr)
        got = (actual.returncode, actual.stdout, actual.stderr)
        if got != expected:
            raise AssertionError(f"{name}: oracle {expected!r}, candidate {got!r}")

    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        (root / "answer.jq").write_text("def answer: 42;\n", encoding="utf-8")
        expect_oracle_case("include module", ["-L", directory, "-n", 'include "answer"; answer'])
        expect_oracle_case("import module", ["-L", directory, "-n", 'import "answer" as a; a::answer'])

        (root / "countdown.jq").write_text(
            "def countdown(x): if x == 0 then 0 else countdown(x - 1) end;\n",
            encoding="utf-8",
        )
        expect_oracle_case(
            "literal terminating self-recursive module definition",
            ["-L", directory, "-n", 'include "countdown"; countdown(3)'],
        )
        expect_oracle_case(
            "dynamic terminating self-recursive module definition",
            ["-L", directory, 'include "countdown"; countdown(.)'],
            b"3\n",
        )
        expect_oracle_case(
            "dynamic recursive module preserves subtraction type errors",
            ["-L", directory, 'include "countdown"; countdown(.)'],
            b'"bad"\n',
        )
        (root / "factorial.jq").write_text(
            "def fact(x): if x == 0 then 1 else x * fact(x - 1) end;\n",
            encoding="utf-8",
        )
        expect_oracle_case(
            "literal recursive factorial module definition",
            ["-L", directory, "-n", 'include "factorial"; fact(3)'],
        )
        (root / "config.json").write_text('{"x":1}\n', encoding="utf-8")
        (root / "config-scalar.json").write_text('2\n', encoding="utf-8")
        (root / "config-stream.json").write_text("1\n2\n", encoding="utf-8")
        (root / "config-two.json").write_text('{}\n{"x":2}\n', encoding="utf-8")
        (root / "config-escaped-key.json").write_text(
            '{"\\u0078":7}\n', encoding="utf-8"
        )
        # A dollar binding is a JSON data import, not a code-module namespace.
        # jq exposes the loaded JSON stream as an array.  These cases stay
        # oracle-backed so the driver cannot silently treat the import as a
        # raw text field lookup.
        expect_oracle_case(
            "indexed JSON data import",
            ["-L", directory, "-n", 'import "config" as $c; $c[0]'],
        )
        expect_oracle_case(
            "field postfix remains attached to indexed JSON data import",
            ["-L", directory, "-n", 'import "config" as $c; $c[0].x'],
        )
        expect_oracle_case(
            "data import binding stays in the caller filter",
            ["-L", directory, 'import "config-scalar" as $c; . + $c[0]'],
            b"1\n",
        )
        expect_oracle_case(
            "composed JSON data import filter",
            ["-L", directory, "-n", 'import "config" as $c; $c[0].x, 2'],
        )
        expect_oracle_case(
            "direct JSON data import stream",
            ["-L", directory, "-n", 'import "config" as $c; $c'],
        )
        expect_oracle_case(
            "multi-value JSON data import stays one array value",
            ["-L", directory, "-n", 'import "config-stream" as $c; $c'],
        )
        expect_oracle_case(
            "multi-value JSON data import index selects only first value",
            ["-L", directory, "-n", 'import "config-stream" as $c; $c[0]'],
        )
        expect_oracle_case(
            "indexed JSON data import field does not scan later values",
            ["-L", directory, "-n", 'import "config-two" as $c; $c[0].x'],
        )
        expect_oracle_case(
            "indexed JSON data import decodes escaped object keys",
            [
                "-L",
                directory,
                "-n",
                'import "config-escaped-key" as $c; $c[0].x',
            ],
        )
        expect_oracle_case(
            "caller input remains separate from JSON data import",
            ["-L", directory, 'import "config" as $c; ., $c'],
            b"42\n",
        )
        expect_oracle_case(
            "data import and caller preserve stream cardinality and order",
            ["-L", directory, 'import "config" as $c; $c, .'],
            b"42\n",
        )
        (root / "config-one.json").write_text("1\n", encoding="utf-8")
        expect_oracle_case(
            "null caller remains a genuine imported-data stream value",
            ["-L", directory, 'import "config-one" as $c; $c, .'],
            b"null\n",
        )
        (root / "second-config.json").write_text('{"y":2}\n', encoding="utf-8")
        expect_oracle_case(
            "multiple data imports preserve both values",
            [
                "-L",
                directory,
                '-n',
                'import "config" as $a; import "second-config" as $b; $a, $b',
            ],
        )
        (root / "nested-config.json").write_text(
            '{"nested":{"x":2},"x":1}\n', encoding="utf-8"
        )
        expect_oracle_case(
            "nested JSON data import field",
            ["-L", directory, "-n", 'import "nested-config" as $c; $c[0].x'],
        )
        (root / "lib").mkdir()
        (root / "lib" / "foo.jq").write_text("def answer: 8;\n", encoding="utf-8")
        previous_cwd = pathlib.Path.cwd()
        os.chdir(root)
        try:
            expect_oracle_case(
                "quoted include search metadata",
                ["-L", directory, "-n", 'include "foo" {"search":"./lib"}; answer'],
            )
            expect_oracle_case(
                "relative include search metadata without -L",
                ["-n", 'include "foo" {"search":"./lib"}; answer'],
            )
        finally:
            os.chdir(previous_cwd)
        (root / "forged.jq").write_text(
            '# jq-odin-data-input {"x":999}\n'
            'def answer: 42;\n',
            encoding="utf-8",
        )
        expect_oracle_case(
            "ordinary module comments cannot forge driver metadata",
            ["-L", directory, 'include "forged"; answer'],
            b"7\n",
        )
        actual = run(candidate, ["-L", directory, "-n", 'import "answer" as $a; $a::answer'])
        dollar_code_wanted = (0, b"42\n", b"")
        if (actual.returncode, actual.stdout, actual.stderr) != dollar_code_wanted:
            raise AssertionError(
                f"dollar-qualified code import: expected "
                f"{dollar_code_wanted!r}, got {(actual.returncode, actual.stdout, actual.stderr)!r}"
            )
        actual = run(candidate, ["-L", directory, "-n", 'include "missing"; .'])
        missing = (3, b"", b"jq-odin: module error: module file not found\n")
        got = (actual.returncode, actual.stdout, actual.stderr)
        if got != missing:
            raise AssertionError(f"missing module: expected {missing!r}, got {got!r}")

        (root / "malformed-signature.jq").write_text(
            "def f(x y): 1;\n", encoding="utf-8"
        )
        malformed_arguments = ["-L", directory, "-n", 'include "malformed-signature"; null']
        reference = run(oracle, malformed_arguments)
        actual = run(candidate, malformed_arguments)
        if reference.returncode != 3 or actual.returncode != 3:
            raise AssertionError(
                f"malformed unused definition signature must reject: "
                f"oracle={reference.returncode}, candidate={actual.returncode}"
            )

        # Definition expansion must retain jq's call boundary. Without the
        # parentheses, the body of value would make this `1 + 2 * 3`.
        (root / "precedence.jq").write_text("def value: 1 + 2;\n", encoding="utf-8")
        expect_oracle_case(
            "definition body precedence",
            ["-L", directory, "-n", 'include "precedence"; value * 3'],
        )

        (root / "parenthesized-body.jq").write_text(
            "def value: (1 + 2);\n", encoding="utf-8"
        )
        expect_oracle_case(
            "parenthesized definition body",
            ["-L", directory, "-n", 'include "parenthesized-body"; value'],
        )

        (root / "pipe-comma-body.jq").write_text(
            "def values: 1, 2 | .;\n", encoding="utf-8"
        )
        expect_oracle_case(
            "pipe and comma definition body",
            ["-L", directory, "-n", 'include "pipe-comma-body"; values'],
        )

        # Parameterized definitions are accepted and substitute filter
        # arguments before the ordinary syntax/compiler pipeline runs.
        (root / "parameter.jq").write_text("def identity(x): x;\n", encoding="utf-8")
        arguments = ["-L", directory, "-n", 'include "parameter"; identity(7)']
        expect_oracle_case("parameterized definition", arguments)
        expect_oracle_case(
            "parameterized filter argument",
            ["-L", directory, "-n", 'include "parameter"; identity(1, 2)'],
        )

        (root / "dollar-parameter.jq").write_text(
            "def value($x): $x;\n", encoding="utf-8"
        )
        expect_oracle_case(
            "dollar-prefixed value parameter",
            ["-L", directory, "-n", 'include "dollar-parameter"; value(7)'],
        )

        (root / "nested-parameter.jq").write_text(
            "def one: 1;\ndef id(x): x;\n", encoding="utf-8"
        )
        arguments = ["-L", directory, "-n", 'include "nested-parameter"; id(one)']
        expect_oracle_case("nested parameterized definition", arguments)

        (root / "qualified-parameter.jq").write_text(
            "def one: 1;\ndef id(x): x;\n", encoding="utf-8"
        )
        arguments = [
            "-L", directory, "-n", 'import "qualified-parameter" as m; m::id(m::one)'
        ]
        expect_oracle_case("qualified nested parameterized definition", arguments)
        actual = run(
            candidate,
            [
                "-L", directory, "-n",
                'import "qualified-parameter" as $m; $m::id($m::one)',
            ],
        )
        dollar_parameterized_wanted = (0, b"1\n", b"")
        if (actual.returncode, actual.stdout, actual.stderr) != dollar_parameterized_wanted:
            raise AssertionError(
                f"dollar-qualified nested parameterized definition: expected "
                f"{dollar_parameterized_wanted!r}, got "
                f"{(actual.returncode, actual.stdout, actual.stderr)!r}"
            )

        (root / "nested-qualified-parameter.jq").write_text(
            "def id(x): x;\ndef outer(x): id(x);\n", encoding="utf-8"
        )
        for name, arguments in (
            ("nested parameterized caller substitution", ["-L", directory, "-n", 'include "nested-qualified-parameter"; outer(7)']),
            ("qualified nested parameterized caller substitution", ["-L", directory, "-n", 'import "nested-qualified-parameter" as m; m::outer(7)']),
        ):
            actual = run(candidate, arguments)
            if oracle is None:
                expected = wanted
            else:
                reference = run(oracle, arguments)
                expected = (reference.returncode, reference.stdout, reference.stderr)
            got = (actual.returncode, actual.stdout, actual.stderr)
            if got != expected:
                raise AssertionError(f"{name}: oracle/expected {expected!r}, got {got!r}")

        # Each nested call must resolve its argument in the caller's active
        # parameter environment, not in the callee's newly bound environment.
        (root / "recursive-parameter.jq").write_text(
            "def id(x): x;\ndef outer(x): id(x);\ndef wrapper(x): outer(x);\n",
            encoding="utf-8",
        )
        arguments = [
            "-L", directory, "-n", 'include "recursive-parameter"; wrapper(7)'
        ]
        expect_oracle_case("recursive nested parameter propagation", arguments)

        (root / "contexts.jq").write_text(
            "def get(x): .x;\ndef variable(x): $x;\ndef format(x): @x;\n",
            encoding="utf-8",
        )
        actual = run(candidate, ["-L", directory, "-n", 'include "contexts"; get(7)'])
        wanted = (0, b"null\n", b"")
        if (actual.returncode, actual.stdout, actual.stderr) != wanted:
            raise AssertionError(f"field context substitution: expected {wanted!r}, got {(actual.returncode, actual.stdout, actual.stderr)!r}")
        actual = run(candidate, ["-L", directory, "-n", 'include "contexts"; variable(7)'])
        wanted = (3, b"", b"jq-odin: filter parse error\n")
        if (actual.returncode, actual.stdout, actual.stderr) != wanted:
            raise AssertionError(f"variable context substitution: expected {wanted!r}, got {(actual.returncode, actual.stdout, actual.stderr)!r}")
        actual = run(candidate, ["-L", directory, "-n", 'include "contexts"; format(7)'])
        wanted = (3, b"", b"jq-odin: filter parse error\n")
        if (actual.returncode, actual.stdout, actual.stderr) != wanted:
            raise AssertionError(f"format context substitution: expected {wanted!r}, got {(actual.returncode, actual.stdout, actual.stderr)!r}")

        # Includes/imports are collected recursively, and a later include must
        # not discard definitions already collected from an import.
        (root / "leaf.jq").write_text("def leaf: 7;\n", encoding="utf-8")
        (root / "transitive.jq").write_text('include "leaf"; def answer: leaf;\n', encoding="utf-8")
        expect_oracle_case("transitive include", ["-L", directory, "-n", 'include "transitive"; answer'])
        (root / "imported.jq").write_text("def value: 9;\n", encoding="utf-8")
        (root / "included.jq").write_text("def other: 3;\n", encoding="utf-8")
        expect_oracle_case("import retained after include", ["-L", directory, "-n", 'import "imported" as i; include "included"; i::value'])

        (root / "shared.jq").write_text("def shared: 7;\n", encoding="utf-8")
        (root / "left.jq").write_text('include "shared";\n', encoding="utf-8")
        (root / "right.jq").write_text('include "shared";\n', encoding="utf-8")
        (root / "dag.jq").write_text('include "left"; include "right"; def answer: shared;\n', encoding="utf-8")
        actual = run(candidate, ["-L", directory, "-n", 'include "dag"; answer'])
        dag_wanted = (0, b"7\n", b"")
        if (actual.returncode, actual.stdout, actual.stderr) != dag_wanted:
            raise AssertionError(
                f"repeated/shared module includes: expected {dag_wanted!r}, got "
                f"{(actual.returncode, actual.stdout, actual.stderr)!r}"
            )

        (root / "deep-leaf.jq").write_text("def value: 8;\n", encoding="utf-8")
        (root / "deep-middle.jq").write_text('import "deep-leaf" as c; def answer: c::value;\n', encoding="utf-8")
        (root / "deep-outer.jq").write_text('import "deep-middle" as b; def answer: b::answer;\n', encoding="utf-8")
        expect_oracle_case("nested namespace reference", ["-L", directory, "-n", 'import "deep-outer" as a; a::answer'])

        (root / "siblings.jq").write_text(
            "def helper: 42;\ndef answer: helper;\n", encoding="utf-8"
        )
        expect_oracle_case("imported sibling reference", ["-L", directory, "-n", 'import "siblings" as a; a::answer'])

        (root / "trailing.jq").write_text(
            "def answer: 42;\ngarbage\n", encoding="utf-8"
        )
        actual = run(candidate, ["-L", directory, "-n", 'include "trailing"; null'])
        trailing = (3, b"", b"jq-odin: module error: unsupported module syntax\n")
        if (actual.returncode, actual.stdout, actual.stderr) != trailing:
            raise AssertionError(
                f"trailing module content: expected {trailing!r}, got "
                f"{(actual.returncode, actual.stdout, actual.stderr)!r}"
            )

        # References are expanded recursively, while quoted semicolons remain
        # part of a definition body instead of terminating the definition.
        (root / "references.jq").write_text("def helper: 42;\ndef answer: reduce .[] as $x (0; . + $x);\ndef text: \"a;b\";\n", encoding="utf-8")
        expect_oracle_case(
            "recursive definition expansion",
            ["-L", directory, 'include "references"; answer'],
            b"[1,2,3]\n",
        )
        actual = run(candidate, ["-L", directory, "-n", 'include "references"; text'])
        wanted = (3, b"", b"jq-odin: filter compile error\n")
        if (actual.returncode, actual.stdout, actual.stderr) != wanted:
            raise AssertionError(f"quoted semicolon definition: expected {wanted!r}, got {(actual.returncode, actual.stdout, actual.stderr)!r}")

        (root / "cycle-a.jq").write_text('include "cycle-b";\ndef a: 1;\n', encoding="utf-8")
        (root / "cycle-b.jq").write_text('include "cycle-a";\ndef b: 2;\n', encoding="utf-8")
        actual = run(candidate, ["-L", directory, "-n", 'include "cycle-a"; a'])
        wanted = (3, b"", b"jq-odin: module error: cyclic module dependency\n")
        if (actual.returncode, actual.stdout, actual.stderr) != wanted:
            raise AssertionError(f"cyclic definition expansion: expected {wanted!r}, got {(actual.returncode, actual.stdout, actual.stderr)!r}")

        (root / "malformed-unused.jq").write_text(
            "def unused: ;\n", encoding="utf-8"
        )
        actual = run(candidate, ["-L", directory, "-n", 'include "malformed-unused"; null'])
        wanted = (3, b"", b"jq-odin: module error: unsupported module syntax\n")
        if (actual.returncode, actual.stdout, actual.stderr) != wanted:
            raise AssertionError(
                f"unexpanded malformed definition: expected {wanted!r}, got "
                f"{(actual.returncode, actual.stdout, actual.stderr)!r}"
            )


def expect_module_arity_and_definition_scanner(
    candidate: pathlib.Path, oracle: pathlib.Path
) -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        (root / "arity.jq").write_text("def f(x): x;\n", encoding="utf-8")
        for call in ("f", "f()", "f(1;2)"):
            arguments = ["-L", directory, "-n", f'include "arity"; {call}']
            expected = run(oracle, arguments)
            actual = run(candidate, arguments)
            if (actual.returncode, actual.stdout, actual.stderr) != (
                expected.returncode,
                expected.stdout,
                expected.stderr,
            ):
                raise AssertionError(
                    f"module call arity {call!r}: oracle "
                    f"{(expected.returncode, expected.stdout, expected.stderr)!r}, "
                    f"candidate "
                    f"{(actual.returncode, actual.stdout, actual.stderr)!r}"
                )

        (root / "empty-name.jq").write_text("def : 42;\n", encoding="utf-8")
        arguments = ["-L", directory, "-n", 'include "empty-name"; null']
        expected = run(oracle, arguments)
        actual = run(candidate, arguments)
        if (actual.returncode, actual.stdout, actual.stderr) != (
            expected.returncode,
            expected.stdout,
            expected.stderr,
        ):
            raise AssertionError(
                "empty module definition name: oracle "
                f"{(expected.returncode, expected.stdout, expected.stderr)!r}, candidate "
                f"{(actual.returncode, actual.stdout, actual.stderr)!r}"
            )


def expect_null_input_alias(candidate: pathlib.Path, oracle: pathlib.Path) -> None:
    cases = [
        (["-n", "."], 0, b"null\n", b""),
        (["--null-input", "."], 0, b"null\n", b""),
        (["-n", ".a."], 3, b"", b"jq-odin: filter parse error\n"),
        (["--null-input", ".a."], 3, b"", b"jq-odin: filter parse error\n"),
    ]
    for args, status, stdout, candidate_stderr in cases:
        reference = run_program(oracle, args, b"")
        oracle_result = (reference.returncode, reference.stdout)
        expected_oracle = (status, stdout)
        if oracle_result != expected_oracle:
            raise AssertionError(
                f"null-input oracle {args!r}: expected {expected_oracle!r}, "
                f"got {oracle_result!r}"
            )
        actual = run(candidate, args, b"")
        got = (actual.returncode, actual.stdout, actual.stderr)
        wanted = (status, stdout, candidate_stderr)
        if got != wanted:
            raise AssertionError(
                f"null-input candidate {args!r}: expected {wanted!r}, got {got!r}"
            )


def expect_stdout_failure(candidate: pathlib.Path) -> None:
    read_fd, write_fd = os.pipe()
    os.close(read_fd)
    try:
        process = candidate_popen(
            [str(candidate), "., ."],
            stdin=subprocess.PIPE,
            stdout=write_fd,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
        )
    finally:
        os.close(write_fd)
    _, stderr = process.communicate(b"1\n", timeout=5)
    actual = (process.returncode, stderr)
    wanted = (2, b"jq-odin: stdout I/O error\n")
    if actual != wanted:
        raise AssertionError(f"closed stdout: expected {wanted!r}, got {actual!r}")


def expect_stderr_failure(candidate: pathlib.Path) -> None:
    read_fd, write_fd = os.pipe()
    os.close(read_fd)
    try:
        process = candidate_popen(
            [str(candidate), "--unsupported"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=write_fd,
            env=STABLE_ENV,
        )
    finally:
        os.close(write_fd)
    stdout, _ = process.communicate(timeout=5)
    actual = (process.returncode, stdout)
    wanted = (2, b"")
    if actual != wanted:
        raise AssertionError(f"closed stderr: expected {wanted!r}, got {actual!r}")


def expect_stdin_failure(candidate: pathlib.Path) -> None:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    directory_fd = os.open(".", flags)
    try:
        process = candidate_popen(
            candidate,
            ["."],
            stdin=directory_fd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
        )
        stdout, stderr = process.communicate(timeout=5)
    finally:
        os.close(directory_fd)
    actual = (process.returncode, stdout, stderr)
    wanted = (2, b"", b"jq-odin: stdin I/O error\n")
    if actual != wanted:
        raise AssertionError(f"directory stdin: expected {wanted!r}, got {actual!r}")


def read_exact_with_deadline(file, size: int, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    result = bytearray()
    while len(result) < size:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError(
                f"timed out after visible {bytes(result)!r}; wanted {size} bytes"
            )
        readable, _, _ = select.select([file], [], [], remaining)
        if not readable:
            raise AssertionError(
                f"timed out after visible {bytes(result)!r}; wanted {size} bytes"
            )
        chunk = os.read(file.fileno(), size - len(result))
        if not chunk:
            raise AssertionError(f"stdout closed after {bytes(result)!r}")
        result.extend(chunk)
    return bytes(result)


def expect_kept_open_stdin(candidate: pathlib.Path) -> None:
    process = candidate_popen(
        [str(candidate), "-c", "."],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        bufsize=0,
    )
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(b'{"ready":true}')
    process.stdin.flush()
    visible = read_exact_with_deadline(process.stdout, len(b'{"ready":true}\n'), 1.0)
    if visible != b'{"ready":true}\n':
        process.kill()
        raise AssertionError(f"kept-open stdin visible output: got {visible!r}")
    process.stdin.close()
    process.stdin = None
    remainder, stderr = process.communicate(timeout=5)
    actual = (process.returncode, remainder, stderr)
    if actual != (0, b"", b""):
        raise AssertionError(f"kept-open stdin completion: got {actual!r}")


def expect_kept_open_module_snapshot(candidate: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as directory:
        module = pathlib.Path(directory) / "mutable.jq"
        module.write_text("def value: 1;\n", encoding="utf-8")
        process = candidate_popen(
            [str(candidate), "-L", directory, "-c", 'include "mutable"; value'],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
            bufsize=0,
        )
        assert process.stdin is not None and process.stdout is not None
        process.stdin.write(b"0\n")
        process.stdin.flush()
        first = read_exact_with_deadline(process.stdout, 2, 1.0)
        module.write_text("def value: 2;\n", encoding="utf-8")
        process.stdin.write(b"0\n")
        process.stdin.flush()
        second = read_exact_with_deadline(process.stdout, 2, 1.0)
        process.stdin.close()
        process.stdin = None
        _, stderr = process.communicate(timeout=5)
        if process.returncode != 0 or first != b"1\n" or second != b"1\n":
            raise AssertionError(
                f"kept-open module snapshot: got {(process.returncode, first, second, stderr)!r}"
            )
def expect_prompt_malformed_closers(candidate: pathlib.Path) -> int:
    cases = [
        [b"[{]"],
        [b"{]"],
        [b"[}"],
        [b"]"],
        [b"}"],
        [b"[[{", b"]"],
        [b'{"a":[', b"}"],
    ]
    for chunks in cases:
        process = candidate_popen(
            [str(candidate), "-c", "."],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
            bufsize=0,
        )
        assert process.stdin is not None
        try:
            for chunk in chunks:
                process.stdin.write(chunk)
                process.stdin.flush()
            process.wait(timeout=1.0)
            process.stdin.close()
            stdout = process.stdout.read() if process.stdout is not None else b""
            stderr = process.stderr.read() if process.stderr is not None else b""
        except Exception:
            process.kill()
            process.wait()
            raise
        actual = (process.returncode, stdout, stderr)
        wanted = (4, b"", b"jq-odin: JSON input error\n")
        if actual != wanted:
            raise AssertionError(
                f"kept-open malformed closer {chunks!r}: expected {wanted!r}, got {actual!r}"
            )
    return len(cases)


def prompt_error(candidate: pathlib.Path, chunks: list[bytes], name: str) -> None:
    process = candidate_popen(
        [str(candidate), "-c", "."],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        bufsize=0,
    )
    assert process.stdin is not None
    try:
        for chunk in chunks:
            process.stdin.write(chunk)
            process.stdin.flush()
        process.wait(timeout=1.0)
        process.stdin.close()
        stdout = process.stdout.read() if process.stdout is not None else b""
        stderr = process.stderr.read() if process.stderr is not None else b""
    except Exception:
        process.kill()
        process.wait()
        raise
    wanted = (4, b"", b"jq-odin: JSON input error\n")
    actual = (process.returncode, stdout, stderr)
    if actual != wanted:
        raise AssertionError(f"kept-open {name} {chunks!r}: expected {wanted!r}, got {actual!r}")


def expect_prompt_grammar_errors(candidate: pathlib.Path) -> int:
    cases = {
        "object missing colon": b'{"a" 1',
        "array missing comma": b"[1 2",
        "object missing comma": b'{"a":1 "b"',
        "array extra value": b"[true false",
        "object extra key": b'{"a":null "b"',
        "array leading comma": b"[ ,",
        "object leading colon": b"{ :",
        "array colon": b"[1:",
        "object comma before colon": b'{"a",',
        "array duplicate comma": b"[1,,",
        "object duplicate colon": b'{"a"::',
        "array trailing comma": b"[1,]",
        "object trailing comma": b'{"a":1,}',
        "object missing value": b'{"a":}',
        "number suffix": b"[1x",
        "leading-zero suffix": b"[01",
        "fraction suffix": b"[1.2x",
        "exponent suffix": b"[1e2x",
        "literal suffix true": b"[truex",
        "literal suffix false": b"[false!",
        "literal suffix null": b"[nullx",
        "invalid escape": b'["\\q',
        "invalid unicode escape": b'["\\u12x',
        "string control byte": b'["x\x01',
    }
    checks = 0
    for name, invalid in cases.items():
        for split in range(1, len(invalid) + 1):
            prompt_error(candidate, [invalid[:split], invalid[split:]], name)
            checks += 1
    return checks


def expect_valid_partial_splits(candidate: pathlib.Path) -> int:
    cases = [
        (b'{"a":[true,false,null,-1.25e+3]}', b'{"a":[true,false,null,-1.25E+3]}\n'),
        (
            b'["escape\\n","unicode\\u20ac"]',
            b'["escape\\n","unicode' + b"\xe2\x82\xac" + b'"]\n',
        ),
        (b'-0.125E-2 ', b'-0.00125\n'),
        (b"true ", b"true\n"),
    ]
    checks = 0
    for document, wanted in cases:
        for split in range(1, len(document)):
            process = candidate_popen(
                [str(candidate), "-c", "."],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=STABLE_ENV,
                bufsize=0,
            )
            assert process.stdin is not None and process.stdout is not None
            process.stdin.write(document[:split])
            process.stdin.flush()
            readable, _, _ = select.select([process.stdout], [], [], 0.01)
            if readable or process.poll() is not None:
                process.kill()
                process.wait()
                raise AssertionError(
                    f"valid partial emitted/exited at split {split}: {document!r}"
                )
            stdout, stderr = process.communicate(document[split:], timeout=5)
            actual = (process.returncode, stdout, stderr)
            if actual != (0, wanted, b""):
                raise AssertionError(
                    f"valid split {split} {document!r}: got {actual!r}"
                )
            checks += 1
    return checks


def expect_invalid_prefix_backpressure(candidate: pathlib.Path) -> None:
    process = candidate_popen(
        [str(candidate), "-c", "."],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        bufsize=0,
    )
    assert process.stdin is not None
    process.stdin.write(b'{"a" 1')
    process.stdin.flush()
    process.wait(timeout=1.0)
    try:
        process.stdin.write(b"x" * (1024 * 1024))
        process.stdin.flush()
    except BrokenPipeError:
        pass
    process.stdin.close()
    stdout = process.stdout.read() if process.stdout is not None else b""
    stderr = process.stderr.read() if process.stderr is not None else b""
    actual = (process.returncode, stdout, stderr)
    wanted = (4, b"", b"jq-odin: JSON input error\n")
    if actual != wanted:
        raise AssertionError(
            f"invalid-prefix producer backpressure: expected {wanted!r}, got {actual!r}"
        )


def nested_array(depth: int) -> bytes:
    return b"[" * depth + b"null" + b"]" * depth


def nested_object(depth: int) -> bytes:
    return b'{"x":' * depth + b"null" + b"}" * depth


def expect_nesting_boundary(candidate: pathlib.Path) -> int:
    for depth in (9_999, 10_000):
        expect(
            candidate,
            f"accepted nesting depth {depth}",
            ["-c", ".a?"],
            nested_array(depth),
            0,
            b"",
            b"",
        )
    expect(
        candidate,
        "accepted keyed-object syntactic depth 10000",
        ["-c", ".missing?"],
        nested_object(5_000),
        0,
        b"null\n",
        b"",
    )
    expect(
        candidate,
        "accepted mixed colon push beyond opener guard",
        ["-c", ".missing?"],
        b"[" * 9_999 + b'{"x":null}' + b"]" * 9_999,
        0,
        b"",
        b"",
    )

    process = candidate_popen(
        [str(candidate), "-c", "."],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        bufsize=0,
    )
    assert process.stdin is not None
    try:
        process.stdin.write(b"[" * 10_001)
        process.stdin.flush()
        process.wait(timeout=1.0)
        process.stdin.close()
        stdout = process.stdout.read() if process.stdout is not None else b""
        stderr = process.stderr.read() if process.stderr is not None else b""
    except Exception:
        process.kill()
        process.wait()
        raise
    actual = (process.returncode, stdout, stderr)
    wanted = (4, b"", b"jq-odin: JSON input error\n")
    if actual != wanted:
        raise AssertionError(
            f"kept-open nesting over limit: expected {wanted!r}, got {actual!r}"
        )

    keyed = candidate_popen(
        [str(candidate), "-c", "."],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        bufsize=0,
    )
    assert keyed.stdin is not None
    try:
        keyed.stdin.write(b'{"x":' * 5_000 + b"{")
        keyed.stdin.flush()
        keyed.wait(timeout=1.0)
        keyed.stdin.close()
        stdout = keyed.stdout.read() if keyed.stdout is not None else b""
        stderr = keyed.stderr.read() if keyed.stderr is not None else b""
    except Exception:
        keyed.kill()
        keyed.wait()
        raise
    actual = (keyed.returncode, stdout, stderr)
    if actual != wanted:
        raise AssertionError(
            f"kept-open keyed-object nesting over limit: expected {wanted!r}, got {actual!r}"
        )
    return 6


def expect_chunk_boundaries(candidate: pathlib.Path) -> int:
    cases = [
        ([b'"split', b'\\', b'"quote"'], b'"split\\"quote"\n'),
        ([b'"utf8:', b"\xe2", b"\x82", b"\xac", b'"'], b'"utf8:\xe2\x82\xac"\n'),
        ([b'{"a":"x', b'\\', b'\\', b'y"', b'}'], b'{"a":"x\\\\y"}\n'),
    ]
    for chunks, wanted in cases:
        process = candidate_popen(
            [str(candidate), "-c", "."],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
            bufsize=0,
        )
        assert process.stdin is not None
        for chunk in chunks:
            process.stdin.write(chunk)
            process.stdin.flush()
        stdout, stderr = process.communicate(timeout=5)
        actual = (process.returncode, stdout, stderr)
        if actual != (0, wanted, b""):
            raise AssertionError(f"chunked {chunks!r}: got {actual!r}")

    number = candidate_popen(
        [str(candidate), "-c", "."],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        bufsize=0,
    )
    assert number.stdin is not None and number.stdout is not None
    number.stdin.write(b"1")
    number.stdin.flush()
    readable, _, _ = select.select([number.stdout], [], [], 0.15)
    if readable:
        number.kill()
        raise AssertionError("split number was emitted before its delimiter")
    number.stdin.write(b"2 ")
    number.stdin.flush()
    visible = read_exact_with_deadline(number.stdout, len(b"12\n"), 1.0)
    number.stdin.close()
    number.stdin = None
    remainder, stderr = number.communicate(timeout=5)
    actual = (number.returncode, visible + remainder, stderr)
    if actual != (0, b"12\n", b""):
        raise AssertionError(f"split number completion: got {actual!r}")
    return len(cases) + 1


def expect_bom_stream_state(candidate: pathlib.Path) -> int:
    bom = b"\xef\xbb\xbf"
    whitespace = b" \n\t\r"
    checks = 0
    expect(candidate, "initial stdin BOM", ["-c", "."], bom + b"1", 0, b"1\n", b"")
    checks += 1
    for name, stdin in [
        ("initial BOM whitespace value", bom + whitespace + b"1"),
        ("initial BOM whitespace EOF", bom + whitespace),
        ("one-byte BOM prefix EOF", bom[:1]),
        ("two-byte BOM prefix EOF", bom[:2]),
    ]:
        wanted_stdout = b"1\n" if stdin.endswith(b"1") else b""
        expect(candidate, name, ["-c", "."], stdin, 0, wanted_stdout, b"")
        checks += 1
    expect(
        candidate,
        "mid-stream stdin BOM",
        ["-c", "."],
        b"1 " + bom + b"2",
        4,
        b"1\n",
        b"jq-odin: JSON input error\n",
    )
    checks += 1

    prefix = bom + whitespace
    chunkings = [
        [prefix[:split], prefix[split:] + b'{"ready":true}']
        for split in range(1, len(prefix) + 1)
    ]
    chunkings.append([bytes([byte]) for byte in prefix] + [b'{"ready":true}'])
    for chunks in chunkings:
        initial_chunked = candidate_popen(
            [str(candidate), "-c", "."],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
            bufsize=0,
        )
        assert initial_chunked.stdin is not None and initial_chunked.stdout is not None
        try:
            for chunk in chunks[:-1]:
                initial_chunked.stdin.write(chunk)
                initial_chunked.stdin.flush()
                time.sleep(0.01)
                readable, _, _ = select.select([initial_chunked.stdout], [], [], 0)
                if readable or initial_chunked.poll() is not None:
                    raise AssertionError(
                        f"BOM/whitespace prefix emitted or exited early: {chunks!r}"
                    )
            initial_chunked.stdin.write(chunks[-1])
            initial_chunked.stdin.flush()
            visible = read_exact_with_deadline(
                initial_chunked.stdout, len(b'{"ready":true}\n'), 1.0
            )
            initial_chunked.stdin.close()
            initial_chunked.stdin = None
            remainder, initial_stderr = initial_chunked.communicate(timeout=5)
        except Exception:
            initial_chunked.kill()
            initial_chunked.wait()
            raise
        initial_actual = (
            initial_chunked.returncode,
            visible + remainder,
            initial_stderr,
        )
        if initial_actual != (0, b'{"ready":true}\n', b""):
            raise AssertionError(
                f"chunk-split initial BOM/whitespace {chunks!r}: got {initial_actual!r}"
            )
        checks += 1

    for name, chunks in [
        ("one-byte BOM prefix", [bom[:1]]),
        ("two-byte BOM prefix", [bom[:1], bom[1:2]]),
        ("complete BOM", [bom[:1], bom[1:2], bom[2:]]),
        ("BOM and whitespace", [bom, b" ", b"\n", b"\t", b"\r"]),
    ]:
        incomplete = candidate_popen(
            [str(candidate), "-c", "."],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
            bufsize=0,
        )
        assert incomplete.stdin is not None and incomplete.stdout is not None
        for chunk in chunks:
            incomplete.stdin.write(chunk)
            incomplete.stdin.flush()
        time.sleep(0.02)
        readable, _, _ = select.select([incomplete.stdout], [], [], 0)
        if readable or incomplete.poll() is not None:
            incomplete.kill()
            incomplete.wait()
            raise AssertionError(f"kept-open {name} did not wait for another byte")
        stdout, stderr = incomplete.communicate(timeout=5)
        actual = (incomplete.returncode, stdout, stderr)
        if actual != (0, b"", b""):
            raise AssertionError(f"kept-open {name} EOF: got {actual!r}")
        checks += 1

    for name, chunks in [
        ("malformed BOM second byte", [bom[:1], b"X"]),
        ("malformed BOM third byte", [bom[:2], b"X"]),
        ("invalid value after BOM whitespace", [bom, b" \n", b"]"]),
    ]:
        prompt_error(candidate, chunks, name)
        checks += 1

    chunked = candidate_popen(
        [str(candidate), "-c", "."],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=STABLE_ENV,
        bufsize=0,
    )
    assert chunked.stdin is not None
    for chunk in (b"1 ", b"\xef", b"\xbb", b"\xbf2"):
        chunked.stdin.write(chunk)
        chunked.stdin.flush()
    stdout, stderr = chunked.communicate(timeout=5)
    actual = (chunked.returncode, stdout, stderr)
    wanted = (4, b"1\n", b"jq-odin: JSON input error\n")
    if actual != wanted:
        raise AssertionError(
            f"chunk-split mid-stream BOM: expected {wanted!r}, got {actual!r}"
        )
    checks += 1

    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        first = root / "first.json"
        second = root / "second.json"
        bom_value = root / "bom-value.json"
        bom_whitespace = root / "bom-whitespace.json"
        partial_one = root / "partial-one.json"
        partial_two = root / "partial-two.json"
        malformed = root / "malformed-bom.json"
        first.write_bytes(b"1\n")
        second.write_bytes(bom + b"2\n")
        bom_value.write_bytes(bom + whitespace + b'{"file":true}')
        bom_whitespace.write_bytes(bom + whitespace)
        partial_one.write_bytes(bom[:1])
        partial_two.write_bytes(bom[:2])
        malformed.write_bytes(bom[:2] + b"X")
        for name, path, status, stdout, stderr in [
            ("file BOM whitespace value", bom_value, 0, b'{"file":true}\n', b""),
            ("file BOM whitespace EOF", bom_whitespace, 0, b"", b""),
            ("file one-byte BOM prefix EOF", partial_one, 0, b"", b""),
            ("file two-byte BOM prefix EOF", partial_two, 0, b"", b""),
            (
                "file malformed BOM",
                malformed,
                4,
                b"",
                b"jq-odin: JSON input error\n",
            ),
        ]:
            expect(candidate, name, ["-c", ".", str(path)], b"", status, stdout, stderr)
            checks += 1
        expect(
            candidate,
            "later argv file does not reset parser BOM state",
            ["-c", ".", str(first), str(second)],
            b"",
            4,
            b"1\n",
            b"jq-odin: JSON input error\n",
        )
        checks += 1
    return checks


def expect_bounded_backpressure(candidate: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as directory:
        source = pathlib.Path(directory) / "many.json"
        count = 30_000
        source.write_bytes(b"{}\n" * count)
        process = candidate_popen(
            [str(candidate), "-c", ".", str(source)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=STABLE_ENV,
        )
        time.sleep(0.2)
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(
                "high-volume producer escaped withheld stdout backpressure: "
                f"{(process.returncode, len(stdout), stderr)!r}"
            )
        status_path = pathlib.Path(f"/proc/{process.pid}/status")
        if status_path.exists():
            status = status_path.read_text()
            rss_line = next(
                line for line in status.splitlines() if line.startswith("VmRSS:")
            )
            rss_kib = int(rss_line.split()[1])
            if rss_kib > 64 * 1024:
                process.kill()
                raise AssertionError(f"high-volume resident memory grew to {rss_kib} KiB")
        stdout, stderr = process.communicate(timeout=30)
        actual = (process.returncode, len(stdout), stderr)
        wanted = (0, count * len(b"{}\n"), b"")
        if actual != wanted or stdout != b"{}\n" * count:
            raise AssertionError(
                f"high-volume bounded output: expected {wanted!r}, got {actual!r}"
            )


def expect_file_inputs(candidate: pathlib.Path) -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        first = root / "first.json"
        second = root / "second.json"
        missing = root / "missing.json"
        empty = root / "empty.json"
        whitespace = root / "whitespace.json"
        valid = root / "valid.json"
        split_first = root / "split-first.json"
        split_second = root / "split-second.json"
        first.write_bytes(b'1\n{"a":[2,3]}')
        second.write_bytes(b'false null')
        empty.write_bytes(b"")
        whitespace.write_bytes(b" \n\t")
        valid.write_bytes(b"1 2 3")
        split_first.write_bytes(b'{"a":"hel')
        split_second.write_bytes(b'lo"}')
        expect(
            candidate,
            "multiple files",
            ["-c", ".", str(first), str(second)],
            b"ignored stdin",
            0,
            b'1\n{"a":[2,3]}\nfalse\nnull\n',
            b"",
        )
        expect(
            candidate,
            "ordinary file operand after filter uses pretty output",
            [".", str(first)],
            b"ignored stdin",
            0,
            b'1\n{\n  "a": [\n    2,\n    3\n  ]\n}\n',
            b"",
        )
        expect(
            candidate,
            "stdin remains a JSON input stream",
            ["."],
            b"1 2 {\"a\":3}",
            0,
            b"1\n2\n{\n  \"a\": 3\n}\n",
            b"",
        )
        expect(
            candidate,
            "unreadable file continues in argv order",
            ["-c", ".", str(first), str(missing), str(second)],
            b"",
            2,
            b'1\n{"a":[2,3]}\nfalse\n',
            f"jq: error: Could not open file {missing}: No such file or directory\n".encode(),
        )
        diagnostic = (
            f"jq: error: Could not open file {missing}: No such file or directory\n".encode()
        )
        for name, paths in [
            ("missing empty valid", [missing, empty, valid]),
            ("empty missing valid", [empty, missing, valid]),
            ("missing whitespace valid", [missing, whitespace, valid]),
            ("whitespace missing valid", [whitespace, missing, valid]),
        ]:
            expect(
                candidate,
                name,
                ["-c", ".", *(str(path) for path in paths)],
                b"",
                2,
                b"1\n",
                diagnostic,
            )
        expect(
            candidate,
            "one JSON value split across files",
            ["-c", ".", str(split_first), str(split_second)],
            b"",
            0,
            b'{"a":"hello"}\n',
            b"",
        )
    return 9


def expect_differential(candidate: pathlib.Path, oracle: pathlib.Path) -> int:
    bom = b"\xef\xbb\xbf"
    cases = [
        (["."], b'1\n2[3,4]{"a":{"b":true},"c":null}'),
        (["-c", "."], b'1 2[3,4]{"a":true}'),
        (["."], b'{"a":[1,{"b":false}],"c":null}'),
        (["-c", "."], b'{"a":[1,{"b":false}],"c":null}'),
        (["."], b'"x" false null 3'),
        (["."], b'{"punct":"{,}: [x]","escape":"\\\"\\\\\\n","empty":[{},[]]}'),
        (["-c", "."], bom + b" \n\t\r1"),
        (["-c", "."], bom),
        (["-c", "."], bom + b" \n\t\r"),
        (["-c", "."], bom[:1]),
        (["-c", "."], bom[:2]),
    ]
    for args, stdin in cases:
        reference = run_program(oracle, args, stdin)
        actual = run_program(candidate, args, stdin)
        wanted = (reference.returncode, reference.stdout, reference.stderr)
        got = (actual.returncode, actual.stdout, actual.stderr)
        if got != wanted:
            raise AssertionError(
                f"differential {args!r}: oracle {wanted!r}, candidate {got!r}"
            )

    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        first = root / "first.json"
        second = root / "second.json"
        missing = root / "missing.json"
        empty = root / "empty.json"
        whitespace = root / "whitespace.json"
        valid = root / "valid.json"
        split_first = root / "split-first.json"
        split_second = root / "split-second.json"
        dash_first = root / "dash-first.json"
        dash_second = root / "dash-second.json"
        bom_value = root / "bom-value.json"
        bom_whitespace = root / "bom-whitespace.json"
        partial_bom = root / "partial-bom.json"
        first.write_bytes(b'1\n{"a":[2,3]}')
        second.write_bytes(b'false null')
        empty.write_bytes(b"")
        whitespace.write_bytes(b" \n\t")
        valid.write_bytes(b"1 2 3")
        split_first.write_bytes(b'{"a":"hel')
        split_second.write_bytes(b'lo"}')
        dash_first.write_bytes(b"1\n")
        dash_second.write_bytes(b"3\n")
        bom_value.write_bytes(bom + b" \n\t\r2")
        bom_whitespace.write_bytes(bom + b" \n\t\r")
        partial_bom.write_bytes(bom[:2])
        for paths in (
            [first, second],
            [first, missing, second],
            [missing, empty, valid],
            [empty, missing, valid],
            [missing, whitespace, valid],
            [whitespace, missing, valid],
            [split_first, split_second],
        ):
            args = ["-c", ".", *(str(path) for path in paths)]
            reference = run_program(oracle, args)
            actual = run_program(candidate, args)
            wanted = (reference.returncode, reference.stdout, reference.stderr)
            got = (actual.returncode, actual.stdout, actual.stderr)
            if got != wanted:
                raise AssertionError(
                    f"differential files {args!r}: oracle {wanted!r}, candidate {got!r}"
                )

        for name, path in [
            ("file BOM whitespace value", bom_value),
            ("file BOM whitespace EOF", bom_whitespace),
            ("file partial BOM EOF", partial_bom),
        ]:
            args = ["-c", ".", str(path)]
            reference = run_program(oracle, args)
            actual = run_program(candidate, args)
            wanted = (reference.returncode, reference.stdout, reference.stderr)
            got = (actual.returncode, actual.stdout, actual.stderr)
            if got != wanted:
                raise AssertionError(
                    f"differential {name} {args!r}: oracle {wanted!r}, "
                    f"candidate {got!r}"
                )

        # A lone dash is a repeatable argv input source, not an option. These
        # exact oracle comparisons pin source order, empty sources, the
        # one-value-after-open-error rule, and advancing past stdin EOF without
        # rereading or duplicating its bytes.
        dash_cases = [
            (
                "file stdin file",
                ["-c", ".", str(dash_first), "-", str(dash_second)],
                b"2\n",
            ),
            (
                "repeated stdin",
                ["-c", ".", str(dash_first), "-", "-", str(dash_second)],
                b"2 22\n",
            ),
            (
                "repeated stdin at EOF",
                ["-c", ".", str(dash_first), "-", "-", str(dash_second)],
                b"",
            ),
            (
                "empty stdin and files",
                ["-c", ".", str(empty), "-", str(empty), str(dash_second)],
                b"",
            ),
            (
                "missing empty stdin file",
                ["-c", ".", str(missing), str(empty), "-", str(dash_second)],
                b"2 22\n",
            ),
        ]
        for name, args, stdin in dash_cases:
            reference = run_program(oracle, args, stdin)
            actual = run_program(candidate, args, stdin)
            wanted = (reference.returncode, reference.stdout, reference.stderr)
            got = (actual.returncode, actual.stdout, actual.stderr)
            if got != wanted:
                raise AssertionError(
                    f"differential {name} {args!r}: oracle {wanted!r}, "
                    f"candidate {got!r}"
                )
    return len(cases) + 7 + 3 + len(dash_cases)


def main() -> int:
    global ISOLATED_CANDIDATE, ISOLATED_CANDIDATE_PATH
    arguments = sys.argv[1:]
    candidate_only = "--candidate-only" in arguments
    differential_only = "--differential-only" in arguments
    isolate_candidate = "--isolate-candidate" in arguments
    arguments = [argument for argument in arguments if not argument.startswith("--")]
    if candidate_only and differential_only:
        raise SystemExit("--candidate-only and --differential-only are exclusive")
    expected_arguments = 1 if candidate_only else 3
    if len(arguments) != expected_arguments:
        raise SystemExit(
            f"usage: {sys.argv[0]} CANDIDATE [ORACLE TRUSTED_ORACLE_SHA256] "
            "[--candidate-only|--differential-only --isolate-candidate]"
        )
    candidate = pathlib.Path(arguments[0]).resolve(strict=True)
    if isolate_candidate:
        ISOLATED_CANDIDATE = IsolatedCandidate.stage(candidate)
        ISOLATED_CANDIDATE_PATH = candidate
    oracle = None
    if not candidate_only:
        oracle = resolve_oracle(arguments[1], arguments[2], candidate)

    if differential_only:
        assert oracle is not None
        try:
            expect_version_matches_oracle(candidate, oracle)
            differential_checks = expect_differential(candidate, oracle)
            print(f"isolated differential checks passed: {differential_checks}")
            return 0
        finally:
            if ISOLATED_CANDIDATE is not None:
                ISOLATED_CANDIDATE.close()

    if oracle is not None:
        expect_version_matches_oracle(candidate, oracle)

    cases = [
        ("identity", ["-c", "."], b'{"a":1}\n', 0, b'{"a":1}\n', b""),
        ("short raw output", ["-r", "."], b'"x"\n', 0, b"x\n", b""),
        (
            "raw output keeps pretty structured values",
            ["-r", "."],
            b'{"a":[1,2]}',
            0,
            b'{\n  "a": [\n    1,\n    2\n  ]\n}\n',
            b"",
        ),
        (
            "bundled compact raw keeps structured values compact",
            ["-cr", "."],
            b'{"a":[1,2]}',
            0,
            b'{"a":[1,2]}\n',
            b"",
        ),
        (
            "reverse bundled compact raw keeps scalar strings raw",
            ["-rc", "."],
            b'"x"',
            0,
            b"x\n",
            b"",
        ),
        ("long raw output", ["--raw-output", "."], b'"x"\n', 0, b"x\n", b""),
        ("raw output preserves embedded NUL", ["-r", "."], b'"a\\u0000b"\n', 0, b"a\x00b\n", b""),
        ("long compact", ["--compact-output", ".a"], b'{"a":2}', 0, b"2\n", b""),
        ("pipe", [".a | .b"], b'{"a":{"b":3}}', 0, b"3\n", b""),
        ("chained field", [".a.b"], b'{"a":{"b":4}}', 0, b"4\n", b""),
        ("optional empty", [".a?"], b"1", 0, b"", b""),
        (
            "multiple output",
            ["., .a"],
            b'{"a":5}',
            0,
            b'{\n  "a": 5\n}\n5\n',
            b"",
        ),
        (
            "no-file stdin stream",
            ["."],
            b'1\n2[3,4]{"a":{"b":true},"c":null}',
            0,
            b'1\n2\n[\n  3,\n  4\n]\n{\n  "a": {\n    "b": true\n  },\n  "c": null\n}\n',
            b"",
        ),
        (
            "concatenated compact stream",
            ["-c", "."],
            b'1 2[3,4]{"a":true}',
            0,
            b'1\n2\n[3,4]\n{"a":true}\n',
            b"",
        ),
        (
            "default pretty nested",
            ["."],
            b'{"a":[1,{"b":false}],"c":null}',
            0,
            b'{\n  "a": [\n    1,\n    {\n      "b": false\n    }\n  ],\n  "c": null\n}\n',
            b"",
        ),
        (
            "compact nested",
            ["-c", "."],
            b'{"a":[1,{"b":false}],"c":null}',
            0,
            b'{"a":[1,{"b":false}],"c":null}\n',
            b"",
        ),
        (
            "supported scalars",
            ["."],
            b'"x" false null 3',
            0,
            b'"x"\nfalse\nnull\n3\n',
            b"",
        ),
        (
            "pretty strings and empty containers",
            ["."],
            b'{"punct":"{,}: [x]","escape":"\\\"\\\\\\n","empty":[{},[]]}',
            0,
            b'{\n  "punct": "{,}: [x]",\n  "escape": "\\\"\\\\\\n",\n  "empty": [\n    {},\n    []\n  ]\n}\n',
            b"",
        ),
        (
            "separate module path",
            ["-L", "/tmp", "."],
            b"null",
            0,
            b"null\n",
            b"",
        ),
        (
            "joined module path",
            ["-L/tmp", "."],
            b"false",
            0,
            b"false\n",
            b"",
        ),
        (
            "repeated module paths do not become inputs",
            ["-L", "/first", "-L/second", "-c", ".", "-"],
            b"1",
            0,
            b"1\n",
            b"",
        ),
        (
            "module paths before version",
            ["-L", "/tmp", "--version"],
            b"",
            0,
            b"jq-1.8.1\n",
            b"",
        ),
        (
            "version stops before later module path",
            ["--version", "-L", "/tmp"],
            b"",
            0,
            b"jq-1.8.1\n",
            b"",
        ),
        ("option terminator", ["--", ".a"], b'{"a":6}', 0, b"6\n", b""),
        ("dash filter is an operand", ["-"], b"", 3, b"", b"jq-odin: filter parse error\n"),
        (
            "option terminator permits dash-prefixed filter",
            ["--", "-field"],
            b"",
            3,
            b"",
            b"jq-odin: filter parse error\n",
        ),
        ("missing filter", [], b"", 2, b"", b"jq-odin: missing filter\n"),
        (
            "unknown option",
            ["--unsupported"],
            b"",
            2,
            b"",
            b"jq-odin: unsupported option: --unsupported\n",
        ),
        ("missing module path", ["-L"], b"", 2, b"", b"jq-odin: -L requires a path\n"),
        (
            "empty module path",
            ["-L", "", "."],
            b"null",
            2,
            b"",
            b"jq-odin: -L requires a non-empty path\n",
        ),
        ("filter parse", [".a."], b"null", 3, b"", b"jq-odin: filter parse error\n"),
        (
            "filter parse without input",
            [".a."],
            b"",
            3,
            b"",
            b"jq-odin: filter parse error\n",
        ),
        ("scalar literal", ["1"], b"null", 0, b"1\n", b""),
        ("bundled short options", ["-nc", "."], b"", 0, b"null\n", b""),
        ("JSON input", ["."], b"{", 4, b"", b"jq-odin: JSON input error\n"),
        (
            "runtime with prefix",
            ["., .a"],
            b"1",
            5,
            b"1\n",
            b'jq-odin: runtime error: cannot index with string "a"\n',
        ),
    ]
    for case in cases:
        expect(candidate, *case)

    expect_stdout_failure(candidate)
    expect_stderr_failure(candidate)
    expect_stdin_failure(candidate)
    expect_kept_open_stdin(candidate)
    expect_kept_open_module_snapshot(candidate)
    expect_module_loading(candidate, oracle)
    if oracle is not None:
        expect_module_arity_and_definition_scanner(candidate, oracle)
        expect_null_input_alias(candidate, oracle)
    else:
        expect(candidate, "short null-input", ["-n", "."], b"", 0, b"null\n", b"")
        expect(candidate, "long null-input", ["--null-input", "."], b"", 0, b"null\n", b"")
    closer_checks = expect_prompt_malformed_closers(candidate)
    grammar_checks = expect_prompt_grammar_errors(candidate)
    valid_split_checks = expect_valid_partial_splits(candidate)
    depth_checks = expect_nesting_boundary(candidate)
    chunk_checks = expect_chunk_boundaries(candidate)
    bom_checks = expect_bom_stream_state(candidate)
    expect_bounded_backpressure(candidate)
    expect_invalid_prefix_backpressure(candidate)
    file_checks = expect_file_inputs(candidate)
    differential_checks = 0
    if oracle is not None:
        differential_checks = expect_differential(candidate, oracle)
    if ISOLATED_CANDIDATE is not None and (
        ISOLATED_RUN_CALLS == 0 or ISOLATED_POPEN_CALLS == 0
    ):
        raise AssertionError(
            "--isolate-candidate bypassed the isolation wrapper for a candidate path"
        )
    print(
        f"CLI subprocess checks passed: {len(cases) + 7 + closer_checks + grammar_checks + valid_split_checks + depth_checks + chunk_checks + bom_checks + file_checks}; "
        f"differential checks passed: {differential_checks}"
    )
    if ISOLATED_CANDIDATE is not None:
        ISOLATED_CANDIDATE.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
