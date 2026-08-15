# Decision 0337: bounded static field filter updates

The root static update `.foo |= FILTER` is now a first-class
`Static_Field_Update` AST/program/evaluator contract. The field operand and
RHS instruction are owned by the compiled program. The evaluator clones the
selected field (missing fields and null roots supply `null`), streams the RHS,
commits the first output only, and destroys the child continuation so later
outputs/errors cannot escape. If the RHS exhausts empty, the object member is
deleted; a null root remains null. Non-object/non-null roots retain jq's typed
string-index error.

The exact `empty` form remains the existing `Static_Field_Delete` opcode, and
literal/static updates remain available. This slice intentionally excludes
nested paths, dynamic keys, and post-update pipe continuation; `.foo.bar |= .`
is a parser near-match rejection. Evidence is in
`compat/static-field-filter-update.jq.test` against pinned jq 1.8.1.
