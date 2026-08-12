# Decision 0227: `map_values` keeps one result per array element

For `map_values`, jq retains the first value emitted by the child filter for
each input element, suppressing later outputs. The evaluator applies the same
per-element first-result rule already used for object values. `map` retains
all child outputs and is intentionally unaffected.

Evidence: `compat/map-values.jq.test:22-25`; jq's definition is in
`upstream/jq/src/builtin.jq:188-190`.
