# Decision 0152: zero-argument `cos` builtin

## Scope

Implement jq's zero-argument `cos` filter for numeric inputs. The parser adds
the `Cos` node, the compiler lowers it to an append-only `Cos` opcode, and the
evaluator computes `math.cos_f64`.

## Evidence

The focused oracle shard `compat/cos.jq.test` records jq 1.8.1 output for `cos`
applied to `0`, positive pi, and negative pi. These points have exact parity
across the pinned oracle and Odin implementation.

## Deferred behavior

Interior values with platform-dependent last digits, non-number diagnostics,
and dynamic or parameterized forms are intentionally deferred. No package
graph or ownership contract changes are required.
