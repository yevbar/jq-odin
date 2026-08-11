# `@text` compatibility shard

The format-family oracle is anchored by `upstream/jq/tests/jq.test:72-82`.
This lane implements zero-argument `@text` for scalar, array, and object
inputs: strings and valid UTF-8 pass through, while values are rendered as
compact JSON (matching jq's `tostring` representation).  Format
arguments/interpolation and sibling formats (`@json`, `@csv`, `@tsv`, `@sh`)
remain deferred.
