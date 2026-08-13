# Predicate path continuation

`path(.[] | select(. > N))` is a bounded evaluator slice. The parser lowers
`select` to `If`, so the evaluator recognizes this exact AST shape and filters
array elements before emitting paths. Arbitrary predicate-valued paths remain
unsupported pending a general resumable filter continuation.

Evidence: `upstream/jq/tests/jq.test:1020-1027` exercises path filters and
`upstream/jq/tests/jq.test:1770-1778` covers select comparisons.
