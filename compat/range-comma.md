# Comma-separated literal range arguments

This shard covers jq's ordered Cartesian expansion for comma-separated
numeric literal arguments in `range`, using the existing literal range
evaluator. Dynamic arguments and generator continuations remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:291-292`.
