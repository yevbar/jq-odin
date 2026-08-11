# Decision 0154: zero-argument `tan` builtin

## Scope

Implement jq's zero-argument `tan` filter for numeric inputs. The parser adds
the `Tan` node, the compiler lowers it to an append-only `Tan` opcode, and the
evaluator computes `math.tan_f64`.

## Evidence

The focused oracle shard `compat/tan.jq.test` records jq 1.8.1 output for `tan`
applied to `-1`, `0`, and `1` radians. These representative points have exact
parity across the pinned oracle and Odin implementation.

## Deferred behavior

Near-pole and interior precision behavior, non-number diagnostics, and dynamic
or parameterized forms are intentionally deferred. No package graph or
ownership contract changes are required.
