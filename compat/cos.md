# `cos` compatibility shard

This shard covers the zero-argument `cos` builtin at zero and the positive and
negative pi endpoints. The evaluator delegates to Odin's `math.cos_f64`.
Interior values with platform-dependent last digits, non-number diagnostics,
and dynamic invocation forms remain deferred.
