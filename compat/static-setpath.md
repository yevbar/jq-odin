# Bounded literal setpath shard

This shard covers `setpath` with a literal path array containing string and
integer components, including nested object/array updates and an empty path.
The path is compiled through the existing literal path representation and the
evaluator performs allocator-owned copy-on-write updates. Dynamic paths,
generator-valued replacements, and `delpaths` remain separate contracts.

Source behavior is pinned to jq 1.8.1's `setpath` cases in
`upstream/jq/tests/jq.test` around lines 1138-1168.
