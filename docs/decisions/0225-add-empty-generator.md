# Decision 0225: bounded `add(empty)` child

The reducer now accepts a literal child generator and consumes its complete
stream. Empty streams return `null`; bounded numeric `range` children reduce in
order. The AST and program instruction retain the existing `Add_Builtin`
discriminants and permit one child operand. The existing identity-bound
`range(.)` continuation is accepted as well. Child filters that already produce
streams, such as `.[]` and parenthesized literal ranges, reuse the same
accumulator frame; other dynamic generators remain deferred.
Comma-separated children are reduced in source order. Literal one-argument
nested ranges are expanded in source order; arbitrary higher-order generators
remain outside this slice.
