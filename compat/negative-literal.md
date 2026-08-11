# Bounded negative numeric literal compatibility shard

This shard covers unary negation when its operand is a numeric literal, both
as a root filter and inside an object constructor. The cases correspond to
`upstream/jq/tests/jq.test:25,39`. Dynamic negation such as `-.` and negative
arguments nested in calls remain deferred.
