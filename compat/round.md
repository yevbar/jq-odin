# `round` compatibility shard

This bounded shard covers the zero-argument numeric `round` builtin for
positive and negative finite numbers. Non-number diagnostics and special
numeric values remain deferred.

Evidence: `upstream/jq/tests/jq.test:2025` and `:2360` exercise `round`;
`compat/round.jq.test:1-8` records the numeric parity slice.
