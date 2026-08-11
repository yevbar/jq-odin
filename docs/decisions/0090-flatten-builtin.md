# Decision 0090: bounded `flatten` builtin

Implement zero-argument `flatten` as an operand-free array transformation.
Nested arrays are traversed depth-first and their scalar leaves are appended
in source order. The implementation uses explicit value ownership and a
bounded recursive helper; argument-bearing depth limits and generator
compositions remain outside this lane. The AST/opcode discriminants append
after the current `ceil` form.
