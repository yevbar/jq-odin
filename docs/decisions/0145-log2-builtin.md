# Decision 0145: base-2 logarithm builtin

`log2` is an append-only operand-free opcode backed by Odin's
`math.log2_f64`; numeric inputs produce their base-2 logarithm. No package
edges or shared contracts change.
