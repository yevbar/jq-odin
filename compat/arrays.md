# `arrays` compatibility shard

This bounded shard covers the zero-argument `arrays` type filter: array input
is passed through, while scalar input yields no output.

Evidence: `upstream/jq/tests/jq.test:1729` exercises `arrays` in a stream;
`compat/arrays.jq.test:1-8` records the pass-through and suppression slice.
Other type predicates remain separate lanes.
