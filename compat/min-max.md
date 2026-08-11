# Bounded min/max compatibility shard

This shard covers zero-argument `min` and `max` over arrays, including the
empty-array `null` result, using the cases at
`upstream/jq/tests/jq.test:1655,1659`. Generator arguments (`min_by`/`max_by`),
non-array diagnostics, and mixed-type edge cases remain deferred.
