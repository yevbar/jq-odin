# Bounded negative numeric literal compatibility shard

This shard covers unary negation when its operand is a numeric literal, both
as a root filter and inside an object constructor. The cases correspond to
`upstream/jq/tests/jq.test:25,39`. A zero mantissa drops the unary sign,
matching jq's `[-1,-0]` result while retaining decimal/exponent spelling
(`-0.0` -> `0.0`). Dynamic negation such as `-.` and negative arguments nested
in calls remain deferred.
