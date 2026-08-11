# Structured `fromjson` compatibility shard

The scalar-only `fromjson` implementation now delegates all JSON text to the
existing `jq:json` parser, preserving owned arrays, objects, strings, and
nested values. The focused cases cover direct structured strings and a
`tojson | fromjson` round trip.

The round-trip source is `upstream/jq/tests/jq.test:106`.
