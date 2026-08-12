# `limit` compatibility shard

This bounded slice covers literal integer counts with array, `range`, and comma
generators. Reaching the count cancels the generator continuation, so a later
error is not evaluated. Zero and negative counts are decided before starting
the generator; negative counts raise jq's catchable literal diagnostic.
Dynamic counts, labels, and broader generator forms remain deferred.

Evidence: `upstream/jq/src/builtin.jq:142-145` and
`upstream/jq/tests/jq.test:361-375,419-423`.
