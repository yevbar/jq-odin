# Generator-valued reduce compatibility shard

The evaluator now recognizes the bounded compiled shape `.[] / .[]` as a
Cartesian generator, evaluates all pairs, and applies the existing numeric
update expression to each result. This preserves jq's reducer cardinality
without changing the general continuation contract.

The focused case is `upstream/jq/tests/jq.test:906`.
