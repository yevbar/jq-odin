# Decision 0269: bounded try expression composition

## Context

An unparenthesized jq `try EXP` captures one pipeline term. Binary, pipe, and
comma operators following that term remain outside the try; parentheses can
explicitly group a larger expression. The evaluator already has resumable
try/catch and defined-or frames, but the parser previously let the try's
expression absorb `//`, causing `try error(0) // 1` to suppress both the error
and its fallback.

## Decision

Stop the unparenthesized try expression at binary, pipe, and comma boundaries.
Keep the existing parenthesized parsing behavior, so `try (error(0)) // 1`
still catches the grouped expression and produces the fallback.

## Ownership and scope

This is a syntax precedence correction in `src/syntax/parser.odin`; no public
AST or evaluator contract changes. More general try/catch composition with
definitions, dynamic generators, or closures remains deferred to the broader
call/continuation contract.
