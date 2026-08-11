# `gmtime`

This shard covers zero-argument conversion of numeric Unix seconds to UTC jq
datetime arrays, including a `gmtime | mktime` round trip. Non-number and
out-of-range timestamp diagnostics remain on the generic runtime path.

Oracle evidence: `upstream/jq/tests/jq.test:1821-1824`.
