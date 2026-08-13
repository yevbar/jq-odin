# Nested data-import aliases

Qualified data aliases consume their namespace segment before applying stream
postfixes such as `[]`, preserving jq's `$d::d[].this` behavior. Data aliases
used as object shorthand are materialized as explicit `"alias": value` pairs
so the ordinary parser retains object-key semantics.

Focused compatibility shard passes 2/2 against pinned jq, covering
`upstream/jq/tests/jq.test:1874-1881`.
