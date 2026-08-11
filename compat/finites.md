# `finites` compatibility shard

This shard covers jq's zero-argument `finites` type filter. Finite numeric
inputs are passed through unchanged; strings, booleans, null, and infinity are
suppressed. jq treats NaN as finite (and serializes it as null), which is
covered by the shard. Dynamic expressions and diagnostics are outside this
bounded lane.

Evidence: jq's builtin definition is anchored at
`upstream/jq/src/builtin.jq:57-61`; `compat/finites.jq.test` records direct
oracle cases.
