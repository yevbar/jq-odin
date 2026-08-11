# `exp10` compatibility shard

This shard covers the zero-argument `exp10` builtin for integer numeric inputs
(`-2`, `-1`, `0`, and `2`). The evaluator uses Odin's `math.pow_f64(10, n)`.
Non-number diagnostics, fractional/platform-sensitive last-digit behavior,
overflow/underflow, and dynamic invocation forms remain deferred.
