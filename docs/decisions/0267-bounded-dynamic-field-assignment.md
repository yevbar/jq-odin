# Bounded dynamic field assignment

The first filter-valued assignment slice is represented explicitly as
`syntax.Node_Kind.Dynamic_Field_Set` and `program.Opcode.Dynamic_Field_Set`.
Its operands are a static field name and one RHS instruction. The evaluator
supports identity, scalar literals, and one field lookup; it evaluates that
RHS against the frame input before replacing/creating the object key.

The contract is intentionally bounded because jq assignments are generators:
a RHS such as `.a = (.b, .c)` must produce one updated object per RHS output,
which requires a resumable assignment continuation rather than a synchronous
opcode branch. The source fact for assignment's filter semantics is
`upstream/jq/tests/jq.test:1116-1128`.
