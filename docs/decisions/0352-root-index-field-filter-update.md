# Root index-to-field filter update

## Decision

Implement the bounded static update shape `.[nonnegative-integer].name |= FILTER`
as a first-class `Static_Index_Field_Update` AST/program opcode. The evaluator
selects the array element, evaluates `FILTER` against the selected field (or
`null` when the element/field is missing), and commits only the first result.
Empty RHS deletes an existing field; empty root input remains `null`, while a
non-empty RHS synthesizes the indexed array/object path as jq does.

## Boundary

Only a root identity followed by one static nonnegative integer and one static
field is lowered. Negative, fractional, dynamic, nested, and multi-selector
paths remain on the general assignment path. The evaluator preserves jq's
typed errors for non-array roots, scalar indexed elements, and non-array
objects.

## Evidence

- Parser shape and static selector checks: `src/syntax/parser.odin:2882-2891`.
- Program operand/child contract: `src/program/package.odin:684-690,855-860`.
- Evaluator first-result continuation and empty/delete handling:
  `src/eval/evaluator.odin:8837-8890,4405-4438,11215-11240`.
- Oracle fixture: `compat/root-index-field-filter-update.jq.test`.
