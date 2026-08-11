# Unicode whitespace trim compatibility shard

The shard covers `trim`, `ltrim`, and `rtrim` over Unicode White_Space code
points. jq's complete whitespace regression is at
`upstream/jq/tests/jq.test:1531`; this focused shard keeps representative
non-ASCII separators and directional behavior.

Dynamic arguments and non-string diagnostics remain deferred.
