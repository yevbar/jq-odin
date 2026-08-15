# Decision 0385: explicit formal-filter reference ABI marker

## Context

The parameterized-call experiment exposed an important jq distinction: a
formal `x` in `def f(x): ...` is a filter closure, while `$x` is an ordinary
lexical value. For example, jq evaluates
`2000 as $x | def f(x): 1 as $x | x; f($x)` to `2000`, but evaluates the
corresponding `$x` body to `1`. Treating the formal as a value binding is
therefore incorrect (see `docs/decisions/0384-formal-filter-argument-evidence.md`).

## Decision

Add an append-only `Parameter_Reference` syntax node and program opcode. The
parser emits it only for formal references in nested definitions, preserving
the existing top-level parameterized lowering. Compiler/program validation
accepts the marker with zero operands, and parser/compiler/program tests assert
that it is distinct from a `$` variable node and survives lowering.

The evaluator deliberately returns `Unsupported_Opcode` for this marker. No
runtime closure activation or value binding is claimed by this phase. A later
phase must carry the formal filter's callable body and establish a call frame
that evaluates that body against the invocation input.

## Ownership and sequencing

The syntax, compiler, program, and evaluator packages are affected. This is a
shared AST/program contract; consumers must add closure-frame activation before
the opcode can be routed in production. Existing zero-argument calls and the
legacy top-level parameterized path remain unchanged.

Source anchors: the marker is declared in `src/syntax/parser.odin:317-320`,
validated/lowered by `src/compiler/package.odin:215-218` and
`src/compiler/package.odin:1697-1699`, stored as an append-only opcode in
`src/program/package.odin:358-362`, and rejected explicitly by
`src/eval/evaluator.odin:8865-8870`.
