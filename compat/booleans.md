# `booleans` compatibility shard

This bounded shard covers the zero-argument `booleans` type filter: boolean
input is passed through, while non-boolean scalar input yields no output.

Evidence: `upstream/jq/tests/jq.test:1749` exercises `booleans` in a stream;
`compat/booleans.jq.test:1-8` records pass-through and suppression.
