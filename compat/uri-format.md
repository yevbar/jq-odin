# URI format filters

This shard covers `@uri` percent-encoding and `@urid` decoding for unreserved
ASCII and UTF-8 codepoints, including a round trip through the URI-safe form.
Scalar non-string values use the existing jq `tostring` coercion path. Other
format filters and exact malformed-input diagnostics remain deferred. Raw
non-ASCII bytes supplied directly to `@urid` are each replaced with U+FFFD,
matching jq's byte-oriented decoder behavior under the harness's C locale.

The UTF-8 cases are anchored to `upstream/jq/tests/jq.test:94-100`.
