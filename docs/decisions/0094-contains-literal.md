# 0094: Add bounded literal-string `contains`

- Status: accepted
- Workstream: syntax/compiler/evaluator

## Context and evidence

jq's string containment cases, including embedded NUL needles, are at
`upstream/jq/tests/jq.test:1404-1427`.

## Decision

Append a `Contains` syntax/program discriminant. Parse
`contains("literal")` into one child string-literal node, lower one instruction
edge, and evaluate only string input with a length-delimited substring search.

## Consequences and limits

This lane avoids introducing a general function-call or continuation contract.
Array/object recursive containment, dynamic arguments, and non-string input
diagnostic parity are explicitly deferred.

## Validation

Run the focused compatibility shard against pinned jq and the Odin candidate,
the pinned Odin build, parser/compiler/evaluator tests, and `make validate`.
Full validation may still stop at the repository's inherited Oniguruma source
pointer check.
