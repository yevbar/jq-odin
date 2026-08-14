# Decision 0326: bounded root `.[] |= empty` update

## Contract

The jq 1.8.1 assignment cases at `upstream/jq/tests/jq.test:1253-1257`
exercise `.[] |= empty`. Arrays and objects produce one empty container;
already-empty containers remain unchanged. Null and scalar inputs raise jq's
catchable `Cannot iterate over ...` diagnostic.

## Implementation

`Static_Iterator_Delete` is a dedicated operand-free syntax/program opcode.
The parser accepts only a root empty-field iterator (`.[]`) and an exact
`empty` RHS (parentheses around `empty` are accepted by the existing parser).
The evaluator validates the input kind, allocates an empty container of the
same kind under the existing allocator, destroys the owned input, and emits
one result. This preserves copy-on-write ownership and stream cardinality
without textual driver rewriting.

## Limits and evidence

Generator-valued RHS filters, nested paths, and other `|=` forms remain
deferred to the generic path-update ABI documented in decision 0324. Focused
oracle parity is recorded in `compat/iterator-delete.jq.test`.
