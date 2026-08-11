# `numbers` compatibility shard

This shard covers jq's zero-argument `numbers` type filter. Numeric inputs are
passed through unchanged; strings, booleans, and null are suppressed. Arrays,
objects, and special-number diagnostics remain outside this bounded lane.

Evidence: jq's builtin definition is anchored at `upstream/jq/src/builtin.jq:57-61`;
`compat/numbers.jq.test` records the direct oracle cases.
