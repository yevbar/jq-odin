# Recursive zero-argument call activation

Status: implemented vertical slice

The zero-argument definition parser now makes the definition name visible
while parsing its body. Recursive references are emitted as `Call` nodes with
a temporary body edge and patched to the completed body root after parsing.
The compiler and Program retain that immutable edge, while Program graph
acyclicity intentionally ignores Call activation edges: calls are runtime
continuations, not structural ownership edges.

The evaluator enters a callee through a real child frame and resumes its
caller on every output. A depth limit of 64 produces a `User_Error` with the
key `recursion depth exceeded`, which is catchable by `try ... catch` and does
not become evaluator misuse or host-stack overflow.

Evidence:

- `src/syntax/parser.odin:550-568` patches recursive call placeholders after
  the definition body has been parsed.
- `src/compiler/package.odin:404-410` treats zero-argument Call bodies as
  non-lexical edges during scope validation.
- `src/program/package.odin:848-855` excludes Call activation edges from the
  immutable graph cycle check.
- `src/eval/evaluator.odin:8047-8072` pushes call frames and raises the bounded
  runtime error.
- `src/driver/driver_test.odin:411-423` verifies recursive errors are
  catchable as ordinary output.
- `docs/decisions/0275-call-frame-contract.md` records the preceding frame
  contract and required probes.

The implementation remains intentionally limited to top-level zero-argument
definitions; parameterized lexical recursion still requires definition-table
and binding-frame ownership.
