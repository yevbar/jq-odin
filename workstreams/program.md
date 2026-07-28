# Program workstream

Own neutral compiled program representation and syntax-to-program lowering.

Do not expose evaluator frames from the program package and do not make the
evaluator import the compiler. Constants that become runtime values must obey
the value ownership contract. Instruction and operand widths must be explicit.

