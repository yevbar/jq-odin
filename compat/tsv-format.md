# `@tsv` compatibility shard

The format-family oracle is anchored by `upstream/jq/tests/jq.test:72-82`.
This lane implements zero-argument `@tsv` for arrays containing scalar fields:
fields are tab-delimited, null fields are empty, and strings escape backslash,
tab, newline, and carriage return as jq does.  Nested arrays/objects, format
arguments/interpolation, and sibling formats remain separate contracts.
