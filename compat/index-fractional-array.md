# Fractional array indices

jq truncates numeric array indices toward zero before lookup. This shard
covers the literal fractional array-index behavior; string indexing and
dynamic index expressions remain covered by their existing contracts.

Oracle evidence: `upstream/jq/tests/jq.test:2413`.
