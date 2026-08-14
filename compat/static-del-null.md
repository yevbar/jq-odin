# Null-base static deletion

This shard covers the jq rule that deleting a static field or numeric-index
path from `null` leaves the input unchanged. The evaluator preserves the null
base before dispatching the path component, so `.foo`, `.[0]`, and nested
`.foo[0]` are no-ops without rewriting the filter or broadening dynamic path
support.
