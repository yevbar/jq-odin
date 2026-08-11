# 0087: Add the bounded `unique` builtin

- Status: accepted
- Workstream: evaluator

## Context and evidence

The jq oracle exercises the zero-argument array form in
`upstream/jq/tests/jq.test:1647-1651`. jq sorts array values and removes
duplicates, including adjacent duplicates after sorting.

## Decision

Append `Unique` to the syntax and program discriminants so existing serialized
forms remain stable. Lower it as a zero-operand builtin and implement an
allocator-owned insertion sort/dedup using the existing evaluator
`compare_values` ordering. Existing values are always transferred to the next
array; only the incoming duplicate is discarded.

## Consequences and limits

The change spans syntax, compiler, program, and evaluator packages. The
verified slice accepts arrays, including mixed scalar values and empty arrays.
Non-array diagnostics and exact jq collation corner cases are intentionally
deferred to a later lane.

## Validation

`compat/unique.jq.test` is the focused oracle shard. Parser/compiler shape
tests and the pinned Odin package tests must pass. The repository's existing
doctor pointer mismatch may still make `make validate` fail independently.
