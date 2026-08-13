# Numeric index-assignment errors

The static numeric index assignment evaluator now follows jq's distinction
between `null` (coerced to an empty array) and other input kinds (typed runtime
errors). Array growth and bounds errors are raised through the normal runtime
error transport, so `try ... catch .` receives the exact jq diagnostic.

Oracle evidence: `upstream/jq/tests/jq.test:229-232` covers the large-index
diagnostic; adjacent jq assignment behavior is verified with the pinned jq
1.8.1 oracle.
