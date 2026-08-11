# `transpose` compatibility shard

This bounded shard covers zero-argument `transpose` for ragged nested arrays,
including null fill, and empty input. Non-array diagnostics remain deferred.

Evidence: `upstream/jq/tests/jq.test:1777-1781` exercises transpose;
`compat/transpose.jq.test:1-9` records the two parity cases.
