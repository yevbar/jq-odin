# `tojson` compatibility shard

The oracle anchors are `upstream/jq/tests/jq.test:106-108` and
`:2158-2190`.  This lane implements zero-argument `tojson` for strings,
scalars, and nested arrays/objects using compact JSON output, including jq's
uppercase exponent spelling.  `fromjson`, format arguments, and arbitrary
number precision remain separate contracts.
