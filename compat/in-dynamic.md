# Dynamic `IN(generator)`

This shard covers uppercase `IN` with one or two resumable generator
arguments. The one-argument form compares each generated value against the
original input. The two-argument form streams the second generator and tests
each value against the first generator, preserving jq's short-circuit/error
ordering. Both forms emit `false` only after exhaustion. `inside` remains a
separate containment contract.
