# Decision 0131: `isnan` is false for non-numbers

The evaluator's `Isnan` opcode now returns `false` for non-number inputs,
matching jq's predicate semantics. Number inputs continue through the existing
NaN classification path. This evaluator-local change does not alter AST,
program, or package graph contracts.

Evidence: `upstream/jq/tests/jq.test:693-694` covers numeric NaN checks;
`compat/isnan-types.jq.test` records the broader type probes.
