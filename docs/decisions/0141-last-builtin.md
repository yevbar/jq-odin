# Decision 0141: zero-argument last selector

`last` is an append-only AST/program opcode lowered as an operand-free leaf.
The evaluator returns the final array element, or null for an empty array or
null input. Generator/parameterized forms and exact wrong-container
diagnostics are intentionally deferred; no package edges or shared ownership
contracts change.
