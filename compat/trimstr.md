# Bounded literal trimstr compatibility shard

This shard covers the literal ASCII `ltrimstr`, `rtrimstr`, and `trimstr`
filters from `upstream/jq/tests/jq.test:1503-1517`. Each separator is a static
string known at compile time. Dynamic separator expressions, non-string input
and separator diagnostics, and Unicode-specific boundary behavior remain
deferred. jq's empty-string edge is covered explicitly: `trimstr("")` and
`rtrimstr("")` emit an empty string, while `ltrimstr("")` is an identity.
