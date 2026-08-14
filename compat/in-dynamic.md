# Dynamic `IN(generator)`

This shard covers the one-argument uppercase `IN` builtin when its argument
is a resumable generator. The evaluator compares each generated value against
the original input, short-circuits on a match, and emits `false` only after
the generator is exhausted. Two-argument `IN(source; s)` and `inside` remain
separate contracts.
