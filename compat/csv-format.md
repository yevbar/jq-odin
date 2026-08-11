# `@csv` compatibility shard

The format-family oracle is anchored by `upstream/jq/tests/jq.test:72-82`.
This lane implements zero-argument `@csv` for arrays containing scalar fields:
strings are quoted with embedded quotes doubled, null fields are empty, and
booleans/numbers use jq-compatible text (including uppercase exponent spelling).
Nested arrays/objects, format arguments/interpolation, and sibling formats
(`@text`, `@json`, `@tsv`, `@sh`) remain separate contracts.
