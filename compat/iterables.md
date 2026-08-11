# `iterables` compatibility shard

This bounded shard covers the zero-argument `iterables` type filter: arrays
and objects are passed through, while scalar input yields no output.

Evidence: `upstream/jq/tests/jq.test:1737` exercises `iterables` in a stream;
`compat/iterables.jq.test:1-12` records array/object pass-through and scalar
suppression. Other type predicates remain separate lanes.
