# Decision 0232: lower bounded `@html` interpolation through existing syntax

Support the literal format-string form `@html "...\(query)..."` without adding
an AST kind, program opcode, evaluator branch, package, or import edge. The
syntax parser lowers literal fragments to existing owned `String` nodes, each
interpolation to `query | @html`, and adjacent segments to existing binary
`Add` nodes. An empty format string lowers to an empty `String` constant.

This mirrors jq's grammar: `StringStart` retains the leading format token,
plain `QQSTRING_TEXT` is appended as a constant, and interpolation appends
`gen_format(Query, format)` (`upstream/jq/src/parser.y:505-530`). The lexer
provides distinct borrowed boundaries and decoded-text token spans
(`upstream/jq/src/lexer.l:99-121`). The synthesized `Add` node's borrowed
`operator_span` is the source span beginning its newly joined segment; ordinary
source binary nodes continue to retain their exact operator token.

All decoded fragment storage remains in the parser's existing private string
allocation registry. Compiler and evaluator ownership are unchanged because
they consume the already-supported `String`, `Pipe`, `Html`, and `Add` forms.
The shared source-AST contract is extended only to allow a synthesized binary
`operator_span` to anchor the source span beginning its newly joined segment;
the affected packages are syntax and its direct compiler consumer. The
compiler's existing validation already accepts that nonempty in-node span, so
it needs no code change. No shared value, program, result, error, ownership, or
import contract changes.

This slice intentionally supports only `@html` format strings. Plain string
interpolation, other format directives with a following string, exhaustive
generated-parser stack parity, and interpolation-specific diagnostics remain
separate work.
