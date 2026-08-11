# Decision 0151: zero-argument `acos` builtin

## Scope

Implement jq's zero-argument `acos` filter for numeric inputs. The parser adds
an `Acos` node, the compiler lowers it to an append-only `Acos` opcode, and the
evaluator computes `math.acos_f64`.

## Evidence

The focused oracle shard `compat/acos.jq.test` records jq 1.8.1 output for
`acos` applied to `-1`, `0`, and `1`, covering the domain endpoints and the
zero input with exact parity.

## Deferred behavior

Interior values with platform-dependent last digits, non-number diagnostics,
out-of-domain handling, and dynamic or parameterized forms are intentionally
deferred. No package graph or ownership contract changes are required.
