# Decision 0113: bounded literal index-family needles

`index`, `rindex`, and `indices` now accept literal numeric and non-empty array
needles in addition to the existing literal string form. The evaluator builds
an owned array for static array literals and compares array elements by jq's
JSON value equality; array needles search contiguous subarrays. Null input
continues to propagate null. Empty array needles, dynamic arguments, and
two-argument forms remain deferred so this lane does not introduce generator
or path-assignment contracts.

The behavior is anchored to `upstream/jq/tests/jq.test:1543-1551` and verified
by `compat/index-family-needles.jq.test` against the pinned jq oracle.
