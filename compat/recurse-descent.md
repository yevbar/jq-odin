# Recursive-descent compatibility shard

This shard covers the standalone `..` term and array collection with `[..]`.
The stream is preorder depth first: it emits the input once, then recursively
visits array elements or object values in iteration order. Scalars and empty
containers therefore emit exactly one value.

Upstream lowers the `..` token to the zero-argument `recurse` builtin
(`upstream/jq/src/parser.y:545-551`). That builtin emits the current input
before recursively applying optional iteration
(`upstream/jq/src/builtin.jq:36-39`). The pinned ordered/cardinality fixture is
`upstream/jq/tests/jq.test:187-189`.

Parameterized `recurse(...)`, dynamic labels, paths, and assignment are outside
this bounded slice.
