# Decision 0136: add the zero-argument `strings` filter

`strings` is represented by append-only syntax and program discriminants,
lowered as a leaf opcode, and evaluated by yielding only string inputs while
suppressing other kinds. It mirrors the existing type-filter family and does
not add a package edge. The lane is based on the numbers filter contract.

Evidence: `upstream/jq/src/builtin.jq:57-61` defines the type-filter family;
`compat/strings.jq.test` provides the focused behavior shard.
