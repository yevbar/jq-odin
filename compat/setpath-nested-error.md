# Nested `setpath` index errors

This shard covers catchable diagnostics when a literal nested array is used as
the first path component. jq reports a typed user error (`Cannot index ... with
array`), rather than silently coercing the container or terminating with an
internal evaluator failure.
