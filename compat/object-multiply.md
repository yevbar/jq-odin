# Recursive object multiplication

The evaluator implements jq's object `*` merge, recursively merging values
when both sides at a key are objects and replacing otherwise.

Oracle evidence: `upstream/jq/tests/jq.test:1713-1725`.
