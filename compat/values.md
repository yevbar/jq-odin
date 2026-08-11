# `values` compatibility shard

This bounded shard covers the zero-argument `values` filter: null input yields
no output, while non-null scalar input is passed through unchanged.

Evidence: `upstream/jq/tests/jq.test:1745` exercises `values` in a stream;
`compat/values.jq.test:1-8` records the null suppression and scalar passthrough
slice. Broader iterator and diagnostic compositions remain deferred.
