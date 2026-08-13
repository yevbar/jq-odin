# Bounded path-mutation runtime errors

This shard covers two literal path-mutation failures whose diagnostics are
observable through `try ... catch`: a non-array `delpaths/1` argument and a
numeric `setpath/2` component applied to an object. The expected messages are
pinned to jq 1.8.1 in `upstream/jq/tests/jq.test:1164-1167` and
`upstream/jq/tests/jq.test:2452-2454`.

The evaluator translates these bounded failures into `Runtime_Error` values so
the existing resumable try/catch continuation can consume the diagnostic
string. Other dynamic path and nested mutation failures remain separate
contracts.
