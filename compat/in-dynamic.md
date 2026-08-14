# Dynamic `IN(generator)`

This shard covers uppercase `IN` with one or two resumable generator
arguments. The one-argument form compares each generated value against the
original input. The two-argument form materializes the first generator's
values, then compares the second generator against that set. Both forms
short-circuit on a match and emit `false` only after exhaustion. `inside`
remains a separate containment contract.
