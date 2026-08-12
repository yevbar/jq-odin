# Decision 0225: bounded `add(empty)` child

The reducer now accepts a literal `empty` child and returns `null`, matching
jq's empty-stream identity. The AST and program instruction retain the existing
`Add_Builtin` discriminants and permit one literal child operand. General
generator-valued `add`, including `add(range(...))`, is deferred until the
shared multi-output continuation contract is expanded.
