# `sinh` compatibility shard

This shard covers the zero-argument `sinh` builtin at `-1`, `0`, and `1`
radians. The evaluator delegates to Odin's generic `math.sinh` implementation.
Near-overflow behavior, interior precision, non-number diagnostics, and dynamic
invocation forms remain deferred.
