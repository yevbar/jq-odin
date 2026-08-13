# Decision 0289: bounded static nested assignment

Static chains such as `.foo[2].bar = 1` and `.foo[2][1] = 1` are represented
as literal path arrays and lowered to the existing `Setpath` opcode. The
existing evaluator owns intermediate object/array creation and runtime errors.
Dynamic index expressions, slices, comma paths, and filter-valued RHS updates
remain outside this contract until a resumable update-path ABI exists.
