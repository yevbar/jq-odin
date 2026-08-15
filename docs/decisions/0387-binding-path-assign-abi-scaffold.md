# Decision 0387: binding-aware path assignment remains an ABI boundary

## Status

Decision-only; no parser/compiler/evaluator source change is made.

## Evidence

For jq.test:2088, `(.a as $x | .b) = "b"` returns
`{"a":1,"b":"b"}` for `{"a":1,"b":2}`, `{"b":"b"}` for `null`,
and typed errors for array/number roots (`Cannot index array/number with string
"a"`). Odin currently reports a generic filter parse error. The non-assignment
`.a as $x | .b` form works, so this is assignment/path capture rather than a
general binding failure.

The assignment parser admits literal/generated path shapes only
(`src/syntax/parser.odin:3460-3505`), while `static_assignment_path` accepts
only Field/Index/Identity (`src/syntax/parser.odin:4312-4352`). The assignment
token is consumed by the binding body's recursive parse, so an early outer
predicate would mis-own the token and lower the body assignment instead.

## Required ABI

A future implementation needs an explicit binding-aware path continuation that
captures the left binding value, evaluates the body as a path-producing filter,
retains zero/one/many paths, and applies RHS copy-on-write with jq error-stream
ordering. It must span parser, compiler/program, and evaluator; source rewriting
or admitting Binding to the literal-path predicate is unsafe.
