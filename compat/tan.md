# `tan` compatibility shard

This shard covers the zero-argument `tan` builtin at `-1`, `0`, and `1`
radians. The evaluator delegates to Odin's `math.tan_f64`. Near-pole,
interior precision, non-number diagnostics, and dynamic invocation forms remain
deferred.
