# `@json` compatibility shard

The format-family oracle is anchored by `upstream/jq/tests/jq.test:72-82`,
with nested JSON values also covered at `:106-108`.  This lane implements the
zero-argument `@json` form for all JSON value kinds using compact JSON output,
including escaped strings and nested arrays/objects.  Format
arguments/interpolation and sibling formats (`@text`, `@csv`, `@tsv`, `@sh`)
remain separate contracts.  Exponent notation is normalized to jq's uppercase
`E` with an explicit positive sign (for example, `1e20` becomes `1E+20`).
