# Comma-separated count streams

This shard covers literal comma-separated count arguments for `limit`, `skip`,
and `nth`, lowered to an ordered sequence of existing two-argument calls.
Dynamic count expressions and generator continuations remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:381-405`.
