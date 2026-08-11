# Empty-string index-family needles

This shard covers jq 1.8's explicit empty-string behavior for `index`,
`rindex`, and `indices`: string inputs return `null`, `null`, and `[]`, while
null input propagates null. The regression is anchored to
`upstream/jq/tests/jq.test:2110-2112`; ordinary non-empty string and array
search remains covered by the existing index-family shards.

Dynamic/two-argument needles and non-string diagnostics remain deferred.
