# `normals` compatibility shard

This shard covers jq's zero-argument `normals` filter. It forwards finite
numbers at or above the IEEE-754 binary64 minimum normal magnitude and
suppresses zero, subnormal values, NaN, infinity, and non-number inputs.
Dynamic expressions and diagnostics remain outside this bounded lane.

Evidence: jq's builtin definition is anchored at
`upstream/jq/src/builtin.jq:57-61`; `compat/normals.jq.test` records direct
oracle cases.
