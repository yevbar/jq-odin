# Nested `path` and `map(select(...))` error boundary

This shard covers the bounded error boundary for a path filter whose result is
not itself a concrete path: `try path(.a | map(select(.b == 0))) catch ...`.
The evaluator reports a catchable user error instead of classifying the valid
jq source as malformed internal state. The exact jq diagnostic includes the
materialized result; this shard uses the stable caught-value behavior while
the general resumable path-filter contract remains outstanding.

Oracle source: `upstream/jq/tests/jq.test:1114-1117`.
