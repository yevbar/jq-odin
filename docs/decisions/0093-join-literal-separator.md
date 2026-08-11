# 0093: Add bounded literal-separator `join`

- Status: accepted
- Workstream: syntax/compiler/evaluator

## Context and evidence

jq's direct join cases cover a literal separator over arrays of strings and
nulls at `upstream/jq/tests/jq.test:444-452` and
`upstream/jq/tests/jq.test:1980-1989`.

## Decision

Append `Join` syntax/program discriminants. Parse `join("literal")` into a
single child string-literal node, lower one instruction edge, and evaluate the
input array with an allocator-owned string builder. Null elements contribute
empty text; string elements are copied between separators.

## Consequences and limits

This lane adds one narrow call form without introducing a general function-call
AST or continuation contract. Dynamic/multiple separators, numeric and boolean
coercion, and object/array diagnostics are explicitly deferred.

## Validation

Run `compat/join.jq.test` against the pinned oracle/candidate, pinned Odin
build, parser/compiler tests, and package tests. Full validation may still stop
at the inherited Oniguruma source-pointer check.
