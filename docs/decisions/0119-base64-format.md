# Decision 0119: bounded base64 format filters

The lexer already tokenizes `@name` formats. For the bounded `@base64` and
`@base64d` slice, the parser emits dedicated operand-free nodes and the
compiler/evaluator append matching opcodes. Evaluation copies the input's
UTF-8 string bytes through Odin's pinned `core:encoding/base64` package, then
constructs an owned jq string. The implementation intentionally does not
accept other format names yet; invalid bytes and non-string diagnostics are
also deferred.

Evidence: `upstream/jq/tests/jq.test:86-92` and
`compat/base64-format.jq.test` against the pinned jq oracle.
