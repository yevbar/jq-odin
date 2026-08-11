# Literal `startswith`/`endswith` compatibility shard

This shard covers literal string arguments for jq's prefix and suffix
predicates, including matching and empty needles. The focused cases follow
the jq compatibility tests at `upstream/jq/tests/jq.test:1487-1491`.

Dynamic arguments, non-string inputs, and general function-call syntax remain
deferred. The evaluator uses byte-delimited string boundaries, matching the
current Odin value representation.
