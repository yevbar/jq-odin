# Decision 0150: zero-argument `asin` builtin

## Scope

Implement jq's zero-argument `asin` filter for numeric inputs. The parser adds
an `Asin` node, the compiler lowers it to an append-only `Asin` opcode, and the
evaluator computes `math.asin_f64`.

## Evidence

The focused oracle shard `compat/asin.jq.test` records jq 1.8.1 output for
`asin` applied to `-1`, `0`, and `1`, covering the domain endpoints and the
identity point with exact parity.

## Deferred behavior

Interior values with platform-dependent last digits, non-number diagnostics,
out-of-domain handling, and dynamic or parameterized forms are intentionally
deferred. No package graph or ownership contract changes are required.
