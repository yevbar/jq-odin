# Decision 0201: bounded `map` stream evaluation

Implement `map(child)` as an array-producing stream consumer. Each input array
element is evaluated independently; every output from the child is appended in
order, then the accumulated array is emitted. Child-frame ownership remains
with the map frame until append succeeds. Non-array diagnostics, assignment,
dynamic definitions, and broader control-flow forms remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:697-705,741-757`.
