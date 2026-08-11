# Decision 0135: add the zero-argument `numbers` filter

`numbers` is represented by append-only syntax and program discriminants,
lowered as a leaf opcode, and evaluated by yielding only number inputs while
suppressing other kinds. It mirrors the existing `arrays`, `objects`,
`booleans`, and `nulls` filters and does not add a package edge.

Evidence: `upstream/jq/src/builtin.jq:57-61` defines the type-filter family;
`compat/numbers.jq.test` provides the focused behavior shard.
