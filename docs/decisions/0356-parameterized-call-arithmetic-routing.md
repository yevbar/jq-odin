# Decision 0356: structurally validated arithmetic callable routing

The one-argument callable runtime now admits a narrow additive body shape:
exactly one parameterized definition, a direct call to that definition, and a
body whose tree contains only `+` nodes with declaration-parameter leaves and
numeric literal leaves. The driver validates this shape from the parsed AST,
including source-span equality for parameter leaves, before selecting the
syntax/compiler/evaluator path. This distinguishes `x` from `.` even though
both source terms lower to an Identity node.

The evaluator therefore executes `def twice(x): x+x; twice(1)` and
`def inc(x): x+1; inc((1,2))` through owned argument/callee frames without
textual substitution. Unsupported bodies, multiple declarations, non-additive
operators, and input-identity bodies remain on the mature module bridge until
their callable contracts are implemented.

Evidence: `src/driver/driver_test.odin` covers additive routing and the `.`
fallback; `compat/parameterized-call-arithmetic.jq.test` passes the same cases
against jq 1.8.1. The routing helper owns and destroys its temporary parser;
the production parser/compiler/evaluator remain unchanged by this gate.
