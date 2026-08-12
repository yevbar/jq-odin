# `mktime`

This shard covers zero-argument conversion of jq parsed datetime arrays to
UTC Unix seconds, including the `strptime | mktime` round trip. One- and
two-field arrays exercise jq's zero-fill rule: the omitted day is zero and
normalizes to the final day of the preceding month. Empty arrays and broader
out-of-range field normalization retain the existing runtime diagnostic path.

Oracle evidence: `upstream/jq/src/builtin.c:1605-1633,1661-1672` and
`upstream/jq/tests/jq.test:1817-1820,1847-1851`.
