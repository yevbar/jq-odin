# Static postfix indexing

This shard covers the bounded `.[N]` and `.field[N]` forms implemented by the
Odin candidate. It compares array lookup, out-of-range null, nested field lookup,
and null passthrough against the pinned jq oracle. The source behavior is
covered by `upstream/jq/tests/jq.test:164-180` and the array-index cases around
`upstream/jq/tests/jq.test:283-287`.

The current slice intentionally supports non-negative integer literals only.
Negative indexes, floating-point coercion, slices, dynamic index expressions,
and assignment/update paths remain separate workstreams.
