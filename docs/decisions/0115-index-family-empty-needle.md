# Decision 0115: empty string index-family needles

The evaluator now follows jq 1.8 for a literal empty-string needle on string
inputs: `index` and `rindex` return null, and `indices` returns an empty array.
Null input continues to propagate null. This is an evaluator-only correction;
dynamic and two-argument forms remain outside the lane.

Evidence: `upstream/jq/tests/jq.test:2110-2112` and
`compat/index-family-empty-needle.jq.test` against the pinned oracle.
