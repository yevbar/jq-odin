# Decision 0316: bounded filter-valued field update

The catalog's whole-filter `.sum = add(.arr[])` is lowered to
`. + {sum: add(.arr[])}`. For an object, object addition overwrites `sum` with
the same RHS value while preserving the other fields. If the input or `.arr[]`
is invalid, both jq forms fail before changing the input. General update-path
and generator-valued assignment frames remain evaluator work.

Evidence: `upstream/jq/tests/jq.test:762` and
`compat/sum-field-update.jq.test`.
