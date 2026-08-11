# `exp` compatibility shard

This shard covers the zero-argument `exp` builtin on representative numeric
inputs (`0`, `1`, `-2`, and `2`). The evaluator delegates to Odin's `math.exp_f64`
and preserves jq's compact numeric serializer output. Non-number diagnostics,
overflow/underflow edges, and dynamic invocation forms remain deferred.
