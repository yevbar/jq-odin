# `scalars` compatibility shard

This bounded shard covers the zero-argument `scalars` type filter: scalar
input, including null, is passed through, while arrays and objects yield no
output.

Evidence: `upstream/jq/tests/jq.test:1741` exercises `scalars` in a stream;
`compat/scalars.jq.test:1-8` records null pass-through and object suppression.
