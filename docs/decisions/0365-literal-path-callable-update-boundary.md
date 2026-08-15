# Literal path arguments still require filter-valued callable updates

The focused probe `def id(x): x |= .; id(.a)` demonstrates the remaining
callable ABI gap. With input `{"a":1}`, pinned jq emits the unchanged root
`{"a":1}`; the Odin CLI rejects the definition/update form as unsupported
module syntax. Existing parameterized-call frames materialize argument outputs
as values, but `.a` must remain a filter evaluated against the caller's root.

Passing only the scalar result loses the path and would emit `1`; rewriting the
body to a scalar operation changes jq's root, cardinality, empty behavior, and
typed errors. Correct support needs filter-vs-value parameter metadata,
caller-root/path-stream ownership across the call frame, update cardinality and
`empty` handling, and path-indexing error propagation. This is the same shared
ABI required by jq.test:1236 (`def inc(x): x |= .+1; inc(.[].a)`).

Do not add a textual expansion or arithmetic-only lowering. The next
implementation must introduce a real callable path/update continuation across
syntax, program, compiler, and evaluator, followed by focused oracle cases and
adversarial semantic/ownership review.
