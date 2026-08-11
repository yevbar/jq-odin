# Literal numeric `range` compatibility shard

This bounded lane supports one-to-three non-negative numeric literal arguments
and emits the jq-compatible half-open numeric stream. Dynamic expressions,
comma-separated generators, negative literal syntax, and `foreach`/`limit`
continuations remain deferred.
