# Negated try operand

The parser must admit `try` as the operand of unary negation, matching jq's
`[-try .]` behavior. Parenthesized `[-(try .)]` was already supported.
