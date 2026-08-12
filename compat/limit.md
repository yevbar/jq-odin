# `limit` compatibility shard

This bounded slice covers literal nonnegative counts with array and `range`
generators. Dynamic counts, comma-separated generators, and detailed
diagnostics remain deferred.

Evidence: `upstream/jq/tests/jq.test:361-373,420-423`.
