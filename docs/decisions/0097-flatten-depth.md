# Decision 0097: bounded literal `flatten(depth)`

- Status: accepted
- Workstream: syntax/compiler/evaluator

## Context and evidence

jq's literal depth cases are at
`upstream/jq/tests/jq.test:1761-1773`.

## Decision

Reuse the existing `Flatten` opcode with an optional single child literal
number operand. A non-negative literal depth traverses top-level array elements
and recursively unwraps at most that many nested array levels; zero-argument
`flatten` retains unlimited traversal. The evaluator validates the child as a
number literal and keeps all value ownership in its existing flatten helpers.

## Limits

Dynamic depth expressions, negative-depth diagnostics, non-array inputs, and
generator/control-flow compositions remain deferred.
