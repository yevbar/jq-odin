# Decision 0315: root identity update

The whole-filter form `. |= try . catch .` is lowered to `.`. The update RHS
is the identity filter wrapped in a catch that is unreachable for this input,
so this preserves jq output and stream cardinality for all JSON values. More
general root/filter-valued updates remain evaluator-owned.

Evidence: `upstream/jq/tests/jq.test:2194` and
`compat/root-identity-update.jq.test`.
