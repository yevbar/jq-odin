# Decision 0276: unary negation accepts try operands

The generated-parser term-start predicate includes `Try`, allowing jq's
`[-try .]` syntax to lower through the existing Negate and Try nodes. This is
a grammar admission only; runtime try/negation ownership is unchanged.
