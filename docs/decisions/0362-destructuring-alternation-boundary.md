# Destructuring `?//` requires an alternation continuation

The current CLI catalog at `/tmp/coverage-dynamic-3d3.json` has 17 executable
failures in the destructuring-alternation cluster (jq.test lines 929, 936,
940, 944, 948, 952, 959, 966, 973, 980, 987, 994, 1001, 1008, 1015, 1022,
and 1029). The lexer already emits an Alternation token (`src/syntax/package.odin:567-575`),
but the parser's object/array pattern branches only accept a pipe body
(`src/syntax/parser.odin:3461-3555`) and the program has no alternation opcode.

Pinned jq 1.8.1 produces successful fallback values for the line-929 shape,
including `[1,null,2,3,null,null]`, `[4,5,null,null,7,null]`, and
`[null,null,null,null,null,"foo"]`; the simpler chained-array cases emit
`3`, `4`, `5`, and `6`. Some malformed projection cases intentionally produce
`Cannot index array with string "c"`. The candidate rejects these forms at
parse time.

This cannot be soundly lowered to the existing `Try`/`Binding` pair. A correct
implementation must retain the original producer value, isolate and roll back
bindings for each pattern branch, fall through only on pattern failure, and
chain two or more alternatives while preserving generator cardinality,
catchable runtime errors, and ownership. The evaluator's current Binding frame
commits one lexical value and runs one body (`src/eval/evaluator.odin:4940-4965`),
whereas Try catch receives an error value rather than a pattern-failure state.
The next implementation phase therefore needs a first-class Alternation AST,
program opcode, and resumable evaluator frame; a parser-only rewrite is
deferred.
