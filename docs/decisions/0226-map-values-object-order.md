# Decision 0226: Preserve object order in `map_values`

`map_values` over an object must visit and rebuild entries in source insertion
order, matching jq. The evaluator's object storage exposes entries in reverse
slot order, so the `Map_Start` path reverses only its object lookup index;
global object iteration remains unchanged. The existing first-result rule for
multi-output children is retained. Array multi-output `map_values` remains
deferred.

Evidence: `compat/map-values.jq.test:14-21`; jq's builtin definition is in
`upstream/jq/src/builtin.jq:188-190`.
