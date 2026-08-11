# Decision 0098: Unicode whitespace for trim builtins

- Status: accepted
- Workstream: evaluator

## Context and evidence

jq's trim whitespace case is `upstream/jq/tests/jq.test:1531`, and jq's
`jvp_codepoint_is_whitespace` implementation is at
`upstream/jq/src/jv_unicode.c:124-139`.

## Decision

Decode UTF-8 code points at the left and right boundaries, recognizing the
Unicode White_Space property set used by jq: U+0009..U+000D, U+0020, U+0085,
U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F, and U+3000.
Preserve the existing ownership and directional trim behavior.

## Limits

Dynamic arguments and non-string diagnostics remain deferred.
