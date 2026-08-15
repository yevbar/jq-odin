# Binding-aware path assignment structural phase

The parser now preserves the exact parenthesized shape
`(.a as $x | .b) = "b"` as a `Binding_Path_Assign` node. The compiler and
Program packages carry that shape as a two-child append-only opcode, and the
evaluator rejects it explicitly as `Unsupported_Opcode` until a continuation
can retain the caller root, binding environment, path cardinality, and typed
root errors. This prevents the ordinary static-field lowering from silently
changing jq semantics.

The focused parser/compiler/program/package checks pass, and the CLI now reaches the
explicit unsupported boundary instead of a generic parse error. Runtime
parity remains deferred under decision 0387; the required oracle behavior is
`{"a":1,"b":2}` -> `{"a":1,"b":"b"}`, with null-base synthesis and typed
array/number errors.
