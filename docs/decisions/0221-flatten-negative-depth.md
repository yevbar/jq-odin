# Decision 0221: negative flatten depth

The bounded flatten-depth parser accepts unary-negative numeric literals and
the evaluator raises the jq-compatible catchable message `flatten depth must
not be negative`. Dynamic depth remains deferred.
