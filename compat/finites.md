# `finites` compatibility shard

This shard covers jq's zero-argument `finites` type filter. Finite numeric
inputs are passed through unchanged; strings, booleans, null, NaN, and
infinity are suppressed. Dynamic expressions and diagnostics are outside this
bounded lane.

Evidence: jq's builtin definition is anchored at
`upstream/jq/src/builtin.jq:57-61`; `compat/finites.jq.test` records direct
oracle cases.
