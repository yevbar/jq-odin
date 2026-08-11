# Decision 0137: finite-number type filter

The `finites` builtin is represented by append-only syntax and program
discriminants. Its evaluator is a leaf filter: it forwards a numeric input
only when `math.is_inf` is false, suppressing every other input. jq's
`isfinite` treats NaN as finite (the serializer emits it as `null`), so NaN is
forwarded while infinities are suppressed. This mirrors jq's `finites` definition without adding package
edges or shared value contracts.

Dynamic generators and diagnostic behavior remain deferred; the focused shard
covers finite numbers, non-number suppression, NaN, and infinity.
