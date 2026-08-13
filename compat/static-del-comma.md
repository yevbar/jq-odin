# Static comma deletion

This shard lowers comma-separated static `del` paths into a sequence of the
existing literal `delpaths` instruction. Each deletion therefore reuses the
established copy-on-write path kernel without introducing a stream-valued path
operand. Dynamic filters, slices, and computed indexes remain separate
continuation contracts.

The behavior is pinned to jq 1.8.1's deletion cases in
`upstream/jq/tests/jq.test` around lines 1168-1178.
