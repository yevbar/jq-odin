# Decision 0202: bounded `map_values` containers

Implement `map_values(child)` for arrays and objects. Arrays retain their
shape; objects retain insertion-ordered keys while each value is evaluated by
the child filter. Multi-output value filters and non-container diagnostics
remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:753-757`.
