# Decision 0176: lower unary `-nan`

## Scope

The parser now permits `nan` and `infinite` after unary minus, and the compiler
lowers unary `-nan` to the existing signless NaN opcode. This matches jq's
observable NaN arithmetic without adding a new value representation.

## Evidence

The fourth case in `compat/string-multiply.jq.test` exercises `nan,-nan` in
string multiplication and passes against pinned jq 1.8.1. The source regression
is `upstream/jq/tests/jq.test:1591`.

## Limits

Unary `-infinite` remains parser/lowering-compatible but is not included in a
separate arithmetic scope; NaN serialization and dynamic unary expressions
remain deferred.
