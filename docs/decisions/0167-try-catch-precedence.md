# Decision 0167: stop unparenthesized catch filters at binary precedence

## Scope

Give the `catch` branch of `try EXP catch EXP` a binary boundary so surrounding
operators remain outside the catch expression. Parenthesized branches continue
to use the full precedence parser.

## Evidence

The focused `compat/try-precedence.jq.test` shard compares additive,
multiplicative, and caught-error forms with pinned jq 1.8.1. Existing static
error and try/catch shards remain covered.

## Deferred

Dynamic catch expressions, labels, assignment, and broader control-flow forms
remain deferred.
