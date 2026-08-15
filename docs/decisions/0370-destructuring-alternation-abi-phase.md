# Decision 0370: retain destructuring alternation as explicit ABI metadata

Status: accepted for the staged parser/program phase; evaluator activation is deferred.

The parser now recognizes the bounded form `PRODUCER as PATTERN ?// PATTERN+ | BODY`
for array and object patterns. It preserves the producer and body directly and stores
each pattern in a linked `Alternation_Branch` descriptor. This is a first-class syntax
and program representation; no driver or source-text rewrite is involved.

Evidence: the node kinds are appended to preserve existing AST ordinals
(`src/syntax/parser.odin:306-310`), the parser builds branch spans and a linked list
(`src/syntax/parser.odin:1186-1255`), and the focused parser assertion checks both
branches (`src/syntax/parser_test.odin:8-27`).

The compiler lowers an `Alternation` instruction with operands ordered as producer,
body, then branch descriptors. A branch descriptor owns one pattern operand. Existing
opcode values remain stable because the new opcodes are appended. The evaluator
explicitly returns `Unsupported_Opcode` for these instructions until transactional
binding activation (including rollback and capture ownership) is implemented.

Evidence: compiler counting and emission are in `src/compiler/package.odin:881-899`
and `src/compiler/package.odin:1259-1280`; program validation is in
`src/program/package.odin:729-734`; evaluator deferral is explicit at
`src/eval/evaluator.odin:8717-8722`.

The focused structural probes are `. as [1] ?// [2] | .` in
`src/syntax/parser_test.odin` and `src/compiler/compiler_test.odin`. They establish
that two branches survive parsing and lowering with immutable operand ownership.

This phase intentionally does not claim runtime jq compatibility for `?//`; evaluator
execution remains the next seam. Malformed forms outside the bounded `as` pattern
shape continue through the existing parser diagnostics.
