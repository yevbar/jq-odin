# Base64 format filters

This shard covers the literal `@base64` and `@base64d` format filters for
ASCII, UTF-8, and scalar-to-string coercion. The filters use Odin's pinned
base64 package and return ordinary jq string values. Other format filters (`@uri`, `@html`,
`@csv`, `@tsv`, `@sh`, and `@json`) and invalid/non-string diagnostics remain
deferred; array/object coercion is not yet implemented for `@base64`.

The cases are anchored to `upstream/jq/tests/jq.test:86-92`.
