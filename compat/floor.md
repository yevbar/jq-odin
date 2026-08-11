# `floor` compatibility shard

This bounded shard covers the zero-argument numeric `floor` builtin for
positive and negative finite numbers. Non-number diagnostics and special
numeric values remain deferred.

Evidence: `upstream/jq/tests/jq.test:821` exercises `floor` in a stream;
`compat/floor.jq.test:1-8` records the numeric parity slice.
