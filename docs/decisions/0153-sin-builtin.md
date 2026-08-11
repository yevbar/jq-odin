# Decision 0153: zero-argument `sin` builtin

## Scope

Implement jq's zero-argument `sin` filter for numeric inputs. The parser adds
the `Sin` node, the compiler lowers it to an append-only `Sin` opcode, and the
evaluator computes `math.sin_f64`.

## Evidence

The focused oracle shard `compat/sin.jq.test` records jq 1.8.1 output for `sin`
applied to `-pi/2`, `0`, and `pi/2`. These points have exact parity across the
pinned oracle and Odin implementation.

## Deferred behavior

Interior values with platform-dependent last digits, non-number diagnostics,
and dynamic or parameterized forms are intentionally deferred. No package
graph or ownership contract changes are required.
