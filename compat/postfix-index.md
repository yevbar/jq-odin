# Static postfix indexing

This shard covers the bounded `.[N]` and `.field[N]` forms implemented by the
Odin candidate. It compares array lookup, out-of-range null, nested field lookup,
and null passthrough against the pinned jq oracle. The source behavior is
covered by `upstream/jq/tests/jq.test:164-180` and the array-index cases around
`upstream/jq/tests/jq.test:283-287`.

The current slice supports integer literals, including comma-separated postfix
index reads and negative indexes resolved from the end of an array. Floating-
point coercion, slices, dynamic index expressions, and assignment/update paths
remain separate workstreams. The comma-separated case is derived from
`upstream/jq/tests/jq.test:283-285`.
