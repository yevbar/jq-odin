# Bounded multi-index selector deletion

The parser already represents a numeric selector list such as
`.foo[1,4,2,3]` as a comma tree of static `Index` nodes, while the evaluator
already owns copy-on-write deletion through `Delpaths`.  This slice lowers
only the exact empty-update form `.foo[<numeric selectors>] |= empty` to that
existing path-deletion ABI.

Deletion paths are ordered by descending non-negative numeric index before
materialization.  This preserves jq's original-coordinate semantics: deleting
index 1 before index 4 would shift the latter and produce the wrong result.
Other selector kinds, dynamic indexes, slices, and filter-valued updates remain
outside this contract and continue to use their existing parser boundaries.

Focused evidence: jq.test:1261 and
`compat/static-field-index-filter-update.jq.test`.
