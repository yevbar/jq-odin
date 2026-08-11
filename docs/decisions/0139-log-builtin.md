# Decision 0139: natural logarithm builtin

`log` is an append-only syntax/program opcode lowered to a leaf evaluator
operation backed by Odin's `math.log`. Numeric inputs are forwarded as their
natural logarithm; non-number inputs use the existing `Cannot_Number` runtime
error. Other logarithm variants (`log10`, `log2`, and dynamic calls) remain
deferred. No package edges or shared value contracts change.
