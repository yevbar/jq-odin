# Decision 0339: one-level nested static index filter update

`Static_Field_Index_Update` is a first-class bounded path-update opcode for
`.name[index] |= FILTER`. It owns two text operands (field and non-negative
index) plus one RHS instruction operand. The evaluator snapshots the selected
element, streams the RHS, commits the first output only, and cancels its child
frames. Empty RHS removes an in-range array element; out-of-range arrays are
unchanged. Missing/null field intermediates remain absent/null on empty and
become arrays when a value is produced. A null root remains null on empty and
becomes an object containing the synthesized array on output.

The implementation deliberately excludes nested paths beyond one static index,
slices, and dynamic indexes. Focused oracle probes are in
`compat/static-field-index-filter-update.jq.test`.
