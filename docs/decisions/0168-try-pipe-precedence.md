# Decision 0168: keep a following pipe outside catch branches

## Scope

The parser gives an unparenthesized `catch` branch a pipe boundary in addition
to its binary boundary. A following pipe therefore consumes the completed
comma stream, matching jq's `try ... catch ..., try ... catch ... | filter`
behavior.

## Evidence

The focused `compat/try-pipe-precedence.jq.test` shard compares the two-output
catch/comma/pipe case with pinned jq 1.8.1. Existing try/binary precedence and
static error shards remain green.

## Deferred

Parenthesized and dynamic control-flow catches, labels, and assignment remain
deferred.
