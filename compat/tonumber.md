# Bounded literal tonumber compatibility shard

This shard covers the zero-argument `tonumber` filter for numeric input and
ordinary numeric strings, including the expression recorded at
`upstream/jq/tests/jq.test:697`. Invalid strings, non-string/non-number input,
dynamic call forms, and precision/diagnostic edge cases remain deferred.
