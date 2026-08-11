# Decision 0074: bounded `not` builtin

Implement `not` as a zero-argument builtin. jq treats only `null` and
`false` as falsey; zero, empty strings, arrays, and objects remain truthy.
The evaluator negates this classification without coercing composite values.
The AST and opcode discriminants are appended after the current integration
head's `isnan` form.
