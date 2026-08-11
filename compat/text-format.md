# `@text` compatibility shard

The format-family oracle is anchored by `upstream/jq/tests/jq.test:72-82`.
This lane implements zero-argument `@text` for scalar inputs: strings and
valid UTF-8 pass through, while numbers, booleans, and null use jq's scalar
text coercion.  Array/object stringification, format arguments/interpolation,
and sibling formats (`@json`, `@csv`, `@tsv`, `@sh`) are deferred.
