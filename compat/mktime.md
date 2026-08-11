# `mktime`

This shard covers zero-argument conversion of jq parsed datetime arrays to
UTC Unix seconds, including the `strptime | mktime` round trip. Invalid and
short datetime arrays retain the existing generic runtime diagnostic path.

Oracle evidence: `upstream/jq/tests/jq.test:1817-1820` and `1847-1851`.
