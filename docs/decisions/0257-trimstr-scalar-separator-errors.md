# Decision 0257: preserve trimstr scalar separators through compilation

## Context

jq parses numeric, boolean, and null arguments to `ltrimstr`, `rtrimstr`,
and `trimstr`. The separator type check occurs during evaluation, which makes
the resulting `startswith() requires string inputs` or
`endswith() requires string inputs` error observable through `try ... catch`.
Rejecting these operands in the parser changes both parse status and jq's
error channel.

## Decision

Admit scalar literal separators in the syntax parser and retain their literal
kind in the existing program instruction. The evaluator emits a `.User_Error`
with jq's operation-specific message before attempting to read a text operand.
No new opcode or operand representation is needed.

## Evidence

- `src/syntax/parser.odin`: scalar trimstr literals are admitted while dynamic
  separators remain rejected.
- `src/compiler/package.odin:1234-1248`: existing literal lowering preserves
  boolean, null, and numeric kinds.
- `src/eval/evaluator.odin`: trimstr dispatch maps non-string literals to the
  catchable jq-compatible messages.
- `compat/trimstr-scalar-errors.jq.test`: focused oracle cases.
