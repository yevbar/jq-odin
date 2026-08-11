# `@sh` compatibility shard

The format-family oracle is anchored by `upstream/jq/tests/jq.test:72-82`.
This lane implements zero-argument `@sh` for scalar and scalar-array fields
using POSIX single-quoting: apostrophes become the `\\''` shell-safe sequence, while null,
boolean, and numeric fields remain unquoted jq text.  Nested containers,
format arguments/interpolation, and shell diagnostic edge cases remain
separate contracts.
