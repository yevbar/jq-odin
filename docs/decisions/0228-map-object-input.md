# Decision 0228: `map` accepts object input

`map(f)` iterates an object’s values and returns an array of transformed
results. Object keys are not retained; `map_values(f)` remains the keyed
object-preserving operation. The evaluator reads object entries in source
order while discarding keys for `map`.

Evidence: `compat/map.jq.test:6-9`; jq's builtin definitions are in
`upstream/jq/src/builtin.jq:180-190`.
