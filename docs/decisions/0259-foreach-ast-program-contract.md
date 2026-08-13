# Decision 0259: Preserve a distinct Foreach AST and program opcode

`foreach EXP as $name (INIT; UPDATE)` is represented separately from `reduce`.
The parser stores the generator, initializer, update, and binding span in a
`Node_Kind.Foreach` node. The compiler lowers those three instruction edges plus
one owned binding-name text operand to a distinct appended `program.Opcode.Foreach`.

The opcode is appended so existing serialized discriminants remain stable.
This change intentionally stops at parser/compiler representation; evaluator
continuation semantics are a follow-up contract.
