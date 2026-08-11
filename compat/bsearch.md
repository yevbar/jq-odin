# Bounded numeric `bsearch` compatibility shard

This lane implements numeric or simple object literal needles against a sorted
array, returning the matching index or jq's negative insertion-point encoding.
Comma-separated numeric literal needles are lowered to an ordinary output
sequence. It uses the existing value ordering comparator. Dynamic arguments,
nested object construction, and non-array diagnostics remain deferred; those forms appear at
`upstream/jq/tests/jq.test:1789-1801`.
