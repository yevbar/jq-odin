# Try expression composition with defined-or

This shard covers jq's precedence rule for an unparenthesized `try EXP`:
the try captures one pipeline term, while a following binary operator remains
outside it. Thus `try error(0) // 1` yields the defined-or fallback. Parentheses
still allow a complete grouped expression to be captured by `try`.

The expected outputs are pinned to jq 1.8.1 in `upstream/jq/tests/jq.test`
and direct oracle probes for the precedence variants in this shard.
