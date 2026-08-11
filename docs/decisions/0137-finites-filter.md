# Decision 0137: finite-number type filter

The `finites` builtin is represented by append-only syntax and program
discriminants. Its evaluator is a leaf filter: it forwards a numeric input
only when neither `math.is_nan` nor `math.is_inf` is true, suppressing every
other input. This mirrors jq's `finites` definition without adding package
edges or shared value contracts.

Dynamic generators and diagnostic behavior remain deferred; the focused shard
covers finite numbers, non-number suppression, NaN, and infinity.
