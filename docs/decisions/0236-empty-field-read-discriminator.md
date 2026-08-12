# Decision 0236: distinguish empty-string field reads from iteration

## Context

jq lowers `term[query]` through indexing, but lowers `term[]` through the
separate `EACH` iterator instruction (`upstream/jq/src/parser.y:601-620`). The
bounded Odin parser represented both `.[]` and `.[""]` as a `Field` with an
empty text operand, so the evaluator treated an empty-string object key as an
iterator request. Object lookup itself accepts every string key and returns
null only when that exact key is absent (`upstream/jq/src/jv_aux.c:80-87`).

## Decision

Add an `Iterator` operand discriminant to the existing compiled `Field`
instruction. The compiler emits it only for the parser's unquoted
empty-bracket sentinel. Program validation requires it to be the final operand
of a two-operand `Field` with no payload. The evaluator selects iterator
behavior from the discriminant, not from the key bytes.

This keeps the existing field child continuation reusable for `.[]` and
ordinary postfix reads while preserving `.[""]` as a read. It adds no AST
kind, opcode, assignment path, update operation, or dynamic index expression.

## Consequences

Empty-string object keys are readable at the root and after another read, and
existing `.[]` array/object streams retain their order and cardinality. The
operand participates in the evaluator's live-program seal, so mutation while a
postfix read is suspended remains malformed-program misuse.

Assignment/update lowering, `path`, dynamic indexes, and dynamic slice bounds
remain deferred because they require contracts beyond this read-only slice.
