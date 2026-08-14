# Decision 0328: bounded static field compound-add contract

## Contract

The jq 1.8.1 case at `upstream/jq/tests/jq.test:1228-1230` exercises
`.foo += .foo`. The selected field and RHS field are read from the original
object, then jq's addition semantics replace the target field. Missing fields
read as `null`; a missing target is created. Null input is materialized as an
object, while arrays/scalars raise `Cannot index ... with string`.

## Implementation

`Static_Field_Add_Field` is a dedicated syntax/program opcode carrying two
owned text operands (target and RHS identifiers). The parser accepts only
`.identifier += .identifier` (including distinct identifiers); other compound
operators, literals, nested paths, and generator RHS forms remain rejected.
The evaluator performs copy-on-write object lookup, applies the existing binary
addition routine, and preserves jq's missing/null, allocation, error, and
stream-cardinality behavior. No generic path-update ABI or textual rewrite is
introduced.

## Evidence and limits

`compat/field-compound-add.jq.test` covers same/different fields, missing/null,
string addition, non-object diagnostics, and near-match rejection. The
defined-or generator case at `upstream/jq/tests/jq.test:1357` remains deferred
to the generic path-update contract because it requires iterator-valued LHS,
short-circuit RHS evaluation, and per-path copy-on-write continuation.
