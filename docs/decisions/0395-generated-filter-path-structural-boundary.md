# Decision 0395: generated `map(select(...))[].field` assignment cannot yet be pinned structurally

Status: decision-only after an isolated parser/compiler probe on `3b1d1bf9`.

## Probe

The target shape is `((map(select(.a == 1))[].b) = 10)`, covering jq.test:1273;
the corresponding filter-update family is jq.test:1277.  The candidate initially
reported a generic parse error.  A strict assignment-hook experiment recognized
the temporary parser nodes (`Field` → empty `Field` → parenthesized `If`) and
wrapped the predicate in a `Map` node, but the compiled root became `Map` rather
than `Path_Assign`.  This means the surrounding `map` call still owns the `=`
token; the resulting graph is not a valid assignment program and must not be
interpreted by the evaluator.

## Source boundary

The ordinary generated-path admission is intentionally limited to root `Index`,
`Comma`, and `Call` shapes (`src/syntax/parser.odin:3452-3471`).  `Path_Assign`
already has a two-child Program/compiler representation
(`src/program/package.odin:739-741`, `src/compiler/package.odin:1684-1690`),
but admitting a nested `Field`/`Map` shape at the later assignment hook races
the generic map-call production (`src/syntax/parser.odin:2301-2303,
2534-2543`) and mis-owns the assignment token.  The evaluator's existing path
continuation (`src/eval/evaluator.odin:8524-8560`) therefore cannot be given a
malformed graph; it has no sound structural node to reject explicitly.

## Required next phase

Introduce a parser-level precedence contract that closes the map argument before
the parenthesized assignment is considered, then add an append-only generated
filter-path assignment opcode and compiler/program tests.  Only after those tests
show a root assignment with `Path → Field(empty) → Map(If)` should evaluator
dispatch return an explicit `Unsupported_Opcode`.  No textual rewrite or
post-parse graph repair is safe.
