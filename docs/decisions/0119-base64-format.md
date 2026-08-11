# Decision 0119: bounded base64 format filters

The lexer already tokenizes `@name` formats. For the bounded `@base64` and
`@base64d` slice, the parser emits dedicated operand-free nodes and the
compiler/evaluator append matching opcodes. Evaluation applies jq's scalar
`tostring` coercion for null, booleans, and numbers, then copies UTF-8 bytes
through Odin's pinned `core:encoding/base64` package and constructs an owned jq
string. Decode validates the alphabet and decoded UTF-8 before constructing the
result, rejecting malformed payloads instead of emitting invalid bytes. The
implementation intentionally does not accept other format names yet; array or
object coercion and exact diagnostics remain deferred.

The reviewed scalar exception is intentional: `null|@base64d` and
`true|@base64d` stringify first and replace malformed decoded sequences with
U+FFFD, matching jq. Invalid bytes from a string payload remain errors.

Evidence: `upstream/jq/tests/jq.test:86-92` and
`compat/base64-format.jq.test` against the pinned jq oracle.
