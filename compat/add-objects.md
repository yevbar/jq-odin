# Object `add` compatibility shard

This shard covers jq's object form of `add`: object values are reduced in
insertion order, and an empty object reduces to `null`. Array reduction remains
covered as a regression. Mixed-type values and non-array/non-object inputs are
outside this bounded lane.

Evidence: `upstream/jq/tests/jq.test:749-766` anchors the add family; the
fixture adds direct object-value reductions against the pinned jq 1.8.1 oracle.
