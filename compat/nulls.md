# `nulls` compatibility shard

This bounded shard covers the zero-argument `nulls` type filter: null input is
passed through, while non-null scalar input yields no output.

Evidence: `upstream/jq/tests/jq.test:1753` exercises `nulls` in a stream;
`compat/nulls.jq.test:1-8` records pass-through and suppression.
