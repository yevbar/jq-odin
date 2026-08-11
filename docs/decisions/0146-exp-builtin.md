# Decision 0146: zero-argument `exp` builtin

## Scope

Implement jq's zero-argument `exp` filter for numeric inputs. The parser adds
an `Exp` node, the compiler lowers it to an append-only `Exp` opcode, and the
evaluator computes `math.exp_f64`.

## Evidence

The focused oracle shard `compat/exp.jq.test` records jq 1.8.1 output for
`exp` applied to `0`, `1`, `-2`, and `2`. These values exercise identity,
positive and negative inputs while avoiding platform-dependent
last-digit and overflow formatting.

## Deferred behavior

Non-number runtime diagnostics, overflow/underflow boundaries, and dynamic or
parameterized forms are intentionally deferred. No package graph or ownership
contract changes are required.
