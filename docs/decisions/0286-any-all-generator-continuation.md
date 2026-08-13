# Parameterized any/all continuation contract

Parameterized `any(generator; predicate)` and `all(generator; predicate)` are
compiled as two instruction operands. The evaluator retains the caller input,
runs the generator as a resumable child, and starts a predicate child for
each generator output. Predicate outputs are consumed for truthiness and are
never emitted. `any` terminates on the first truthy predicate result; `all`
terminates on the first falsey result. Empty generators produce `false` and
`true`, respectively. Decisive results destroy all active generator/predicate
frames before returning the boolean to the caller, which is required for
`any(true,error(...); .)` and its `all` analogue.

The zero-argument and `any(not)`/`all(not)` forms retain their existing leaf
opcodes. This contract intentionally does not add labels/break or general
definition calls.
