# `map_values` compatibility shard

This slice covers one child filter over arrays and insertion-ordered object
values, preserving object keys. Multi-output value filters and non-container
diagnostics remain deferred.

Evidence: `upstream/jq/tests/jq.test:753-757`.
