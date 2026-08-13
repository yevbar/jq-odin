# Decision 0285: current while/until continuation contract

## Context

The current evaluator had no `while` or `until` syntax, opcode, or frame phase.
The historical bounded implementation could not be transplanted because it
predated the current Call, Foreach, path, and assignment contracts.

## Decision

Add `While` and `Until` as appended syntax/program forms with two instruction
children: condition and update. Evaluation uses explicit phases for condition
and update activation, retained child result, and output/termination. A while
loop emits the current input while the condition is truthy, then updates and
rechecks; an until loop updates until the condition becomes truthy and emits
the final value. Child filters may be generators; the first supported loop
contract requires exactly one condition/update result per iteration and treats
multiple or empty child streams as malformed continuation state.

## Evidence

The focused shard `compat/while-until-current.jq.test` matches jq 1.8.1 for
the scalar loops and array `until` consumer. Upstream references are
`upstream/jq/tests/jq.test:311` and `:329`.

## Follow-up

Multi-output conditions/updates and label/break unwinding remain separate
contracts; they must not be emulated by silently selecting one stream value.
