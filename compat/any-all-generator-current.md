# Parameterized any/all generator continuation

This shard exercises the two-filter forms `any(generator; predicate)` and
`all(generator; predicate)`. The evaluator keeps the original input for the
generator, feeds each generator output into the predicate, suppresses
non-decisive predicate outputs, and short-circuits decisive results. Empty
generators use jq's identity defaults (`false` for `any`, `true` for `all`).

Oracle evidence: `upstream/jq/tests/jq.test:1036-1057`.
