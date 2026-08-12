# `map` compatibility shard

This slice supports array input with one general child filter, including child
filters that emit multiple values. Non-array diagnostics and assignment,
dynamic function definitions, and broader control-flow forms remain deferred.
Literal comma-separated child filters and dotted optional array iteration are
also covered.

Evidence: `upstream/jq/tests/jq.test:697-705,741-757`.
