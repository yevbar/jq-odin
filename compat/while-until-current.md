# Current while/until continuation shard

This shard covers the first current-base loop contract: scalar and identity
condition/update filters, including a generator consumer around `until`. The
loop owns its input, retains one child result, and re-enters condition/update
frames explicitly; it does not rely on Odin call-stack recursion.

Oracle evidence: `upstream/jq/tests/jq.test:311` and `:329`.
