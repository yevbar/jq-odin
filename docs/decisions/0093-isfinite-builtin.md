# Decision 0093: bounded `isfinite` builtin

Implement `isfinite` as an operand-free predicate. It returns true only for
finite binary64 numbers and false for NaN, infinities, and non-number values,
matching jq's predicate contract. The AST and opcode discriminants append
after the current `all` form; broader parser call forms remain deferred.
