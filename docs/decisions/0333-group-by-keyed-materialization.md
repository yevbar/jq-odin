# Decision 0333: bounded static `group_by(.field)` keyed materialization

The parser now lowers unary static `group_by(.field)` into a real AST
materialization pipeline: `map([[key,value]]) | sort_by_key | group_by_key`.
`Group_By_Key` is an appended program opcode that groups adjacent equal keys
while preserving value order within each group. This reuses the reviewed
stable-key comparator used by bounded `sort_by(.field)` and keeps the ordinary
`sort` opcode unchanged.

The implementation accepts a comma-separated tuple of static field selectors
and static arithmetic/comparison expressions for `sort_by` and `group_by` (for
example, `sort_by(.a,.b)` and `group_by(.a + .b - .c == 2)`). Dynamic key
filters, variables, postfix paths, and generator-valued expressions remain
deferred; those require resumable key-stream evaluation and jq's exact runtime
error/cardinality behavior. The focused fixture `compat/group-by-keyed.jq.test`
covers direct grouping, composition, tuple-key ordering, and one static
expression key.
