# Decision 0028: Lower nested static index assignment through setpath

The jq compatibility cases at `upstream/jq/tests/jq.test:213-217` require
`.foo[-1] = 0` and `.foo[-2] = 0` to produce a catchable `Out of bounds
negative array index` error when the input is `null`. The bounded static-index
assignment opcode previously accepted only a root identity (`.[-1]`), so the
nested forms were rejected by the parser.

For this bounded slice, the parser lowers a field-plus-index target such as
`.foo[-1]` to the existing literal `setpath` representation. The evaluator
already owns copy-on-write creation of missing object fields and array index
diagnostics, so this avoids introducing a second nested-assignment opcode or a
new ownership path. The lowering remains limited to a static field, numeric
index, and scalar RHS; generator-valued assignments remain outside this
contract.
