# Decision 0176: lower unary `-nan`

## Scope

The parser now permits `nan` and `infinite` after unary minus, and the compiler
lowers both forms to the existing signless special-number opcodes. This
matches jq's observable NaN/infinity predicates without adding a new value
representation.

## Evidence

The fourth case in `compat/string-multiply.jq.test` exercises `nan,-nan` in
string multiplication, and the special-number shard covers `-infinite |
isinfinite`; both pass against pinned jq 1.8.1. The source regressions are
`upstream/jq/tests/jq.test:1591` and `689-693`.

## Limits

General unary arithmetic on special values, NaN serialization, and dynamic
unary expressions remain deferred.
