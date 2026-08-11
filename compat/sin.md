# `sin` compatibility shard

This shard covers the zero-argument `sin` builtin at zero and the positive and
negative pi/2 endpoints. The evaluator delegates to Odin's `math.sin_f64`.
Interior values with platform-dependent last digits, non-number diagnostics,
and dynamic invocation forms remain deferred.
