# Negative flatten depth

Literal negative `flatten` depths parse and produce jq's catchable runtime
diagnostic. Dynamic depth expressions remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:1773-1775`.
