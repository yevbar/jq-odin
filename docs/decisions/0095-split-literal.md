# 0095: Add bounded literal-string `split`

- Status: accepted
- Workstream: syntax/compiler/evaluator

## Context and evidence

jq's ordinary string split cases are at
`upstream/jq/tests/jq.test:1495-1499` and `1575-1579`.

## Decision

Append a `Split` syntax/program discriminant. Parse `split("literal")` into a
single child string-literal node, lower one instruction edge, and evaluate a
string input by splitting on each non-empty literal separator occurrence.

## Consequences and limits

This lane avoids introducing a general function-call or continuation contract.
Empty-separator Unicode code-point semantics, dynamic/array separators, and
non-string input diagnostic parity are explicitly deferred.

## Validation

Run the focused compatibility shard against pinned jq and the Odin candidate,
the pinned Odin build, parser/compiler/evaluator tests, and `make validate`.
Full validation may still stop at the repository's inherited Oniguruma source
pointer check.
