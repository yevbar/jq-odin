# `strings` compatibility shard

This shard covers jq's zero-argument `strings` type filter. String inputs are
passed through unchanged; numbers, booleans, and null are suppressed. Arrays,
objects, and malformed-input diagnostics remain outside this bounded lane.

Evidence: jq's builtin definition is anchored at `upstream/jq/src/builtin.jq:57-61`;
`compat/strings.jq.test` records direct oracle cases.
