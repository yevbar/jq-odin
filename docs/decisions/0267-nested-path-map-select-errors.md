# Decision: classify unsupported nested path filters as runtime errors

`path(f)` must reject filters whose result is not a concrete path, but a
well-formed filter such as `path(.a | map(select(.b == 0)))` is a jq runtime
error and must remain visible to `try ... catch`. The evaluator therefore
raises `User_Error` with the stable `Invalid path expression` key when its
bounded path recognizers cannot derive a path. It does not claim to implement
arbitrary predicate-valued path continuation; that remains a separate
resumable-frame contract.

Evidence: `upstream/jq/tests/jq.test:1114-1117`.
