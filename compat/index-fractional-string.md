# Fractional string-index diagnostics

This shard covers the bounded case where a literal fractional numeric index is
applied to a string. jq reports `Cannot index string with number`; the
evaluator now preserves that runtime error instead of returning `null`.

The source behavior is exercised by `upstream/jq/tests/jq.test:2445`.
Dynamic indices, assignment/update forms, and other indexing diagnostics remain
outside this shard.
