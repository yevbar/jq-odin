# Empty-value `reverse` compatibility shard

This bounded shard covers jq's zero-length reverse behavior: null, numeric
zero, an empty string, and an empty object each produce an empty array. Array
reversal remains a regression. Non-zero numbers, non-empty strings, and
non-empty objects retain jq's indexing errors and remain outside this lane.

Evidence: `upstream/jq/tests/jq.test:2365-2369` anchors reverse-related
behavior; the fixture records direct oracle probes for the zero-length values.
