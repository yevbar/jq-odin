# Decision 0185: preserve unary negative infinity

Unary `-infinite` lowers to an owned `-Infinity` numeric literal instead of
reusing the positive `Infinite` opcode. This preserves the sign for jq's
arithmetic and serialization behavior while leaving `-nan` signless.
