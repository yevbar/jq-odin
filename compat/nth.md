# `nth` compatibility shard

This bounded slice covers literal nonnegative indexes with existing array and
`range` generators. Dynamic indexes, comma-separated generators, negative
indexes, and detailed diagnostics remain deferred.

Evidence: `upstream/jq/tests/jq.test:393-405,425-425`.
