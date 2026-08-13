# Bounded literal delpaths shard

This shard covers `delpaths` when its argument is a statically literal array
of literal path arrays. It handles object and array deletion, nested paths,
multiple paths, missing paths, and deletion of the root with an empty path.
The evaluator applies each path using owned copy-on-write values and preserves
jq's array index shifting. Dynamic path generators and runtime errors for
invalid container/component combinations remain separate contracts.

Source behavior is pinned to jq 1.8.1's `delpaths` cases in
`upstream/jq/tests/jq.test`.
