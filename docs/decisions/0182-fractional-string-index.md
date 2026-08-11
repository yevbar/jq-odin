# Decision 0182: preserve fractional string-index errors

The bounded indexing evaluator keeps `null` for non-integral array indices but
returns jq's runtime error class for a non-integral numeric index on a string.
This matches `upstream/jq/tests/jq.test:2445` while avoiding a broader indexing
or assignment contract change.
