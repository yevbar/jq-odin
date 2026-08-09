# 0029: Neutral unary-negation program lowering

- Status: proposed
- Date: 2026-08-09
- Workstream: program

## Context and evidence

The pinned jq grammar treats unary minus as a recursive `'-' Term` production
(`upstream/jq/src/parser.y:652-654`). The emitted jq block places the operand
before a call to the internal `_negate` builtin, so the operation applies to
the complete recursive term rather than only to a numeric token
(`upstream/jq/src/parser.y:652-654`). The current syntax package already owns
`Node_Kind.Negate` with a child reference.

## Decision

Unary negation remains compiler-deferred until the eval owner can add and
dispatch a new program opcode. The program package pins every existing
`Opcode` discriminant explicitly, so adding `Negate` later must append it at a
new value without renumbering existing opcodes. Until that sequencing change,
`compiler.lower_filter` validates negation syntax but returns `Invalid_AST`
before allocation; it does not emit an executable or neutral identity opcode.
When the eval change is ready, `Negate` should have
exactly one `Operand_Kind.Instruction` operand, pointing to the child node;
its source span is retained and it has no operator span or literal metadata.
At that point, `compiler.lower_filter` may count and emit this operand in
syntax-arena order.
The compiler does not allocate a `value.Value` and does not expose evaluator
frames or runtime error behavior.

## Sequencing and ownership

This is a sequencing contract for the integration coordinator and eval owner.
The focused compiler test is compile-only: it proves the parser/compiler
boundary rejects the not-yet-executable feature without allocation or a
partial Program. The program/compiler slice makes no claim that unary
negation is executable jq behavior.

No package or import edge changes. Program owns the instruction graph and
compiler owns the borrowed-syntax-to-program transition. The Program remains
the sole owner of instruction storage; the child index is a fixed-width `u32`
handle and does not borrow syntax memory.

## Validation

Focused compiler tests validate `-.`, grouped and composed negation, and nested
negation while asserting deferred, allocation-free rejection. Program tests
pin all serialized opcode discriminants, including the pre-existing binary
opcodes. jq source parity is covered by the grammar citation above. Required
adversarial lanes are source-aware semantic parity, Odin ownership/safety, and
eval sequencing/test-gap review.
