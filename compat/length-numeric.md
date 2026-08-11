# Numeric `length` compatibility shard

This shard covers jq's numeric `length` rule: the result is the absolute
numeric value. It also retains null, string, and array regressions to ensure
the evaluator's existing collection behavior is unchanged. Boolean and object
diagnostics remain outside this bounded lane.

Evidence: `upstream/jq/tests/jq.test:728-732` covers collection/string length;
the numeric rule is confirmed against the pinned jq 1.8.1 oracle with
`-1.5 | length` and `0 | length`.
