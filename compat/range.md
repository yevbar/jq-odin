# Literal numeric `range` compatibility shard

This bounded lane supports one-to-three non-negative numeric literal arguments
and emits the jq-compatible half-open numeric stream. A bounded comma-separated
sequence of one-argument literal generators is also supported. Dynamic
expressions and `foreach`/`limit` continuations remain deferred.
