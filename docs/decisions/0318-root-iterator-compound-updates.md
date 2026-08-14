# Decision 0318: bounded root iterator compound updates

The parser lowers only a root `.[]` path with a numeric literal RHS and one of
`+=`, `-=`, `*=`, `/=`, or `%=` to the existing static iterator update opcode,
with an explicit operator tag in the program instruction. The evaluator applies
the corresponding numeric operation independently to each array/object value.

This keeps the existing `.[] = scalar` and `.[] |= empty` contracts intact and
does not generalize assignment to arbitrary paths, filter-valued RHSs, or
generator updates. The operator tag is part of the program ABI so evaluation
does not reinterpret source text.
