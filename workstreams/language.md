# Language workstream

Own jq tokens, lexer, parser, and source-level syntax tree.

Keep source literals independent of runtime `Value`. Cite `src/lexer.l`,
`src/parser.y`, compile-error tests, precedence behavior, and source locations.
Begin with parser probes that can be checked without an evaluator.

