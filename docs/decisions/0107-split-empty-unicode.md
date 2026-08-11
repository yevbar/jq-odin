# Decision 0107: empty-separator Unicode `split`

The existing literal `split` evaluator now treats an empty separator as a
Unicode codepoint boundary. It emits one owned string per UTF-8 codepoint and
returns an empty array for empty input, matching the jq case at
`upstream/jq/tests/jq.test:1499` while preserving ordinary non-empty separator
behavior.

Dynamic/array separators, malformed UTF-8, and non-string diagnostics remain
deferred. No AST, program, or package graph contract changes are required.
