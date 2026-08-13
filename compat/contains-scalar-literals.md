# Scalar `contains` literals

The pinned jq oracle accepts JSON scalar literals as the needle for
`contains/1`; the parser must preserve the literal node so the existing
containment evaluator can apply jq's scalar equality semantics.
