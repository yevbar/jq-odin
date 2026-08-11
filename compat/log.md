# `log` compatibility shard

This shard covers the zero-argument numeric `log` builtin for positive,
zero, and negative finite numbers. Non-number diagnostics and exact platform
formatting outside these oracle values remain deferred.

Evidence: jq's builtin math behavior is exercised by
`compat/log.jq.test` against the pinned jq 1.8.1 oracle.
