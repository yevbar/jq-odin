# Decision 0237: bounded static numeric field update

- Status: accepted
- Date: 2026-08-12
- Workstream: eval, with task-scoped syntax/program/compiler integration

## Context and evidence

jq gives `|=` a token distinct from `+=` and the other assignment operators
(`upstream/jq/src/parser.y:80-85`) and places the assignment family in one
non-associative precedence level (`upstream/jq/src/parser.y:100-108`). The
general `Expr |= Expr` form lowers through `_modify`
(`upstream/jq/src/parser.y:364-365`), while recursive path replacement reads a
subvalue and sets the updated result back into the root
(`upstream/jq/src/jv_aux.c:409-428`). The bounded observable target is
`.foo |= .+1` on `{"foo":42}`, yielding `{"foo":43}`
(`upstream/jq/tests/jq.test:1212-1214`).

## Decision

Append `Static_Field_Add_Number` to the syntax and program discriminants. The
parser admits only a standalone static field on the left and the exact
identity-plus-number shape on the right. The program owns two consecutive text
operands: field name and numeric spelling. The evaluator takes the root object,
copies the selected member, applies existing jq addition, and replaces that
member through `value.object_set_take`; unrelated members and insertion order
remain intact.

Output capacity is reserved before mutation. On successful replacement the
evaluator transfers the root out of its frame, so no shallow duplicate owner is
created. Failed value-layer mutation consumes neither key nor replacement and
therefore leaves the frame retryable.

## Alternatives

A general assignment AST/opcode was rejected because `.[]`, nested/dynamic
paths, deletion by `empty`, and multi-output update filters require a path and
continuation ownership contract. Literal `setpath`/`delpaths` was also rejected
for this slice because recursive array/object creation and deletion have a
larger value-mutation surface than one existing object member.

## Consequences

No package or import edge is added. The append-only discriminants affect
`syntax`, `program`, `compiler`, and `eval` together. All other assignment
tokens and update shapes remain unsupported, as do missing fields and
non-object roots.

## Validation

Run the focused syntax/compiler/evaluator tests and
`compat/static-field-update.jq.test`, followed by the pinned build,
`make check-packages`, `make test`, `make test-cli`, `make validate`, and the
full 522-case catalog. Adversarial review should probe parser precedence,
object ownership after replacement, allocator retry before mutation, and
rejection of broader update shapes.
