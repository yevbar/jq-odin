# Decision 0148: zero-argument `exp2` builtin

## Scope

Implement jq's zero-argument `exp2` filter for numeric inputs. The parser adds
an `Exp2` node, the compiler lowers it to an append-only `Exp2` opcode, and the
evaluator computes `math.pow_f64(2, n)`.

## Evidence

The focused oracle shard `compat/exp2.jq.test` records jq 1.8.1 output for
`exp2` applied to `-2`, `-1`, `0`, and `3`. Integer exponents provide exact
parity while exercising fractional, identity, and positive results.

## Deferred behavior

Non-number diagnostics, fractional/platform-dependent last digits,
overflow/underflow boundaries, and dynamic or parameterized forms are
intentionally deferred. No package graph or ownership contract changes are
required.
