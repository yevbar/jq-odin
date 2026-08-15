# Decision 0350: bounded filtered iterator deletion

The exact path shape `(.[] | select(predicate)) |= empty` is lowered to the
existing resumable root iterator update. Each item runs an `if predicate then
empty else . end` child, so selected items are deleted while non-selected
items are retained. This covers jq.test:1253 without introducing a generic
path-update opcode or a textual driver rewrite.

The focused shard `compat/filtered-iterator-delete.jq.test` covers matching
and non-matching array elements. Filter-valued updates other than the exact
empty deletion shape, nested paths, and generator-valued path expressions
remain separate contracts.
