# Decision 0144: base-10 logarithm builtin

`log10` is an append-only operand-free opcode backed by Odin's
`math.log10_f64`; numeric inputs produce their base-10 logarithm and other
input kinds use the existing numeric runtime error. No package edges change.
