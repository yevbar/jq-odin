# `skip` compatibility shard

This bounded slice covers literal nonnegative counts with array and `range`
generators. Dynamic counts, comma-separated generators, negative-count
diagnostics, and broader continuation forms remain deferred.

Evidence: `upstream/jq/tests/jq.test:377-389`.
