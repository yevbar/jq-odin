# Invalid string escape diagnostic

## Decision

Carry the parser's borrowed lexical-error message through `driver.Run_Error`
and render the bounded string-escape diagnostic in the CLI. The parser already
consumes the complete offending escape candidate and reports its source span;
this phase adds no AST, evaluator, or ownership changes.

## Evidence

The pinned jq.test:63 probe is:

```jq
"u\vw"
```

jq reports `Invalid escape at line 1, column 4 (while parsing '"\v"')`, then
the top-level source location at column 3 with a two-byte caret over `\v`, and
exits with status 3. The scanner groups the candidate at
`src/syntax/package.odin:346-356`; parser lexical failures preserve the span and
message at `src/syntax/parser.odin:6693-6710`.

The driver stores the borrowed parse message alongside `filter_start` and
`filter_end` (`src/driver/package.odin:462-472, 1289-1299`), while
`cmd/jq-odin/main.odin` formats the nested escape context and source caret.

## Boundary

This only formats lexical errors with a parser-provided message. Unexpected
tokens, unterminated strings, and multi-line escape-context rendering retain
their existing generic parse diagnostics until separately specified.
