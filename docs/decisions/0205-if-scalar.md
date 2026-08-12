# Decision 0205: bounded scalar conditionals

The evaluator now supports `if CONDITION then THEN else ELSE end` with one
condition and two scalar branches. The condition is truthy unless it is null
or false. Generator conditions, `elif`, and dynamic continuation forms are
deferred because they require broader continuation semantics.

The AST and opcode are append-only to preserve serialized discriminants.
