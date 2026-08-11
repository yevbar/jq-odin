# Decision 0149: zero-argument `exp10` builtin

## Scope

Implement jq's zero-argument `exp10` filter for numeric inputs. The parser adds
an `Exp10` node, the compiler lowers it to an append-only `Exp10` opcode, and
the evaluator computes `math.pow_f64(10, n)`.

## Evidence

The focused oracle shard `compat/exp10.jq.test` records jq 1.8.1 output for
`exp10` applied to `-2`, `-1`, `0`, and `2`. Integer exponents provide exact
parity while exercising fractional, identity, and positive results.

## Deferred behavior

Non-number diagnostics, fractional/platform-dependent last digits,
overflow/underflow boundaries, and dynamic or parameterized forms are
intentionally deferred. No package graph or ownership contract changes are
required.
