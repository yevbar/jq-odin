# Decision 0329: exact static `.field |= .?` identity update

The jq 1.8.1 case at `upstream/jq/tests/jq.test:2335` is a bounded identity
update. Existing fields are preserved; missing fields and null input materialize
an object field with null; non-object inputs raise `Cannot index ... with
string`.

`Static_Field_Optional_Identity` is a dedicated operand-bearing opcode. The
parser accepts only `.identifier |= .?` (parenthesized `.?` is accepted by the
existing transparent-parentheses rule), while `.identifier |= .`, `empty`,
compound operators, and generator RHS forms remain rejected. The evaluator
looks up the selected field, substitutes null when absent, and writes it back
copy-on-write, preserving ownership and one-result cardinality.

This does not claim generic path-update support; `.[] |= try tonumber` remains
deferred because it needs resumable per-element RHS streams and deletion/error
continuations.
