# Decision 0225: bounded `add(empty)` child

The reducer now accepts a literal child generator and consumes its complete
stream. Empty streams return `null`; bounded numeric `range` children reduce in
order. The AST and program instruction retain the existing `Add_Builtin`
discriminants and permit one child operand. The existing identity-bound
`range(.)` continuation is accepted as well; other dynamic generators remain
deferred.
