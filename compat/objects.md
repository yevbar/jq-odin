# `objects` compatibility shard

This bounded shard covers the zero-argument `objects` type filter: object
input is passed through, while scalar input yields no output.

Evidence: `upstream/jq/tests/jq.test:1733` exercises `objects` in a stream;
`compat/objects.jq.test:1-8` records the pass-through and suppression slice.
Other type predicates remain separate lanes.
