# Decision 0120: bounded URI format filters

The lexer/parser/compiler append dedicated operand-free `Uri` and `Urid`
forms. Evaluation percent-encodes UTF-8 bytes using the RFC 3986 unreserved
set (`A-Z`, `a-z`, `0-9`, `-._~`) and decodes `%HH` sequences back to UTF-8,
rejecting malformed escapes or invalid UTF-8. The filters reuse the base64
lane's scalar `tostring` coercion and owned string construction. Other format
filters and exact diagnostics remain deferred. Direct raw non-ASCII codepoints
are intentionally replaced byte-by-byte with U+FFFD under the harness's C
locale; percent-encoded UTF-8 remains decoded to its original codepoint.

Evidence: `upstream/jq/tests/jq.test:94-100` and
`compat/uri-format.jq.test` against the pinned jq oracle.
