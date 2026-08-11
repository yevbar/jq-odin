# All-value `tostring` compatibility shard

This shard covers jq's `tostring` coercion: strings remain raw, while null,
booleans, numbers, arrays, and objects are rendered as compact JSON text.
Malformed values and detailed number-format edge cases remain deferred.

Evidence: `upstream/jq/tests/jq.test:2148-2158` anchors tostring behavior;
the fixture records direct scalar/container oracle probes.
