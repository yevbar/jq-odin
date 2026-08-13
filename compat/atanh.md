# `atanh` compatibility shard

This shard covers the zero-argument numeric `atanh` filter at zero, the ±1
boundary, and out-of-domain values. The implementation uses Odin's native
`math.atanh` and preserves the existing evaluator error/ownership contract.
The ordinary non-boundary value and non-number diagnostic are deferred because
the current native-number serializer and typed-error rendering differ in their
last observable spelling.
