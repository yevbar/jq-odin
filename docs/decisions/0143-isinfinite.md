# Decision 0143: infinity predicate

`isinfinite` is an append-only operand-free opcode. The evaluator returns
`math.is_inf` for numeric input and false for all other kinds, matching jq's
predicate contract without new package edges.
