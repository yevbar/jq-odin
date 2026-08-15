# Filter-valued parameter updates need a callable/path continuation

jq.test:1236 uses `def inc(x): x |= .+1; inc(.[].a)`. On
`[{"a":1},{"a":2}]`, pinned jq emits the updated root
`[{"a":2},{"a":3}]`; the current CLI rejects the form as unsupported module
syntax. The already-supported arithmetic callable route cannot substitute
`x + 1`: jq emits scalar `2` and `3` for that body, not the updated root.
Array-valued fields also preserve jq's arithmetic error, and a null root
reports `Cannot iterate over null (null)`.

The parser/compiler/evaluator callable frame currently supports a bounded
value-parameter arithmetic tree, while `x |= FILTER` requires the parameter to
retain a path/update continuation and apply a filter-valued RHS to the caller's
selected paths. Correct support needs filter-vs-value parameter metadata,
caller path-stream ownership, update cardinality/empty semantics, and typed
errors across the callable frame. A textual module rewrite or lowering the
body to arithmetic would change observable root/cardinality behavior, so this
case remains deferred pending that shared ABI.
