# 0088: Add the bounded `sort` builtin

- Status: accepted
- Workstream: evaluator

## Context and evidence

The jq oracle's direct `sort` case is at
`upstream/jq/tests/jq.test:1635-1637`. It orders null, booleans, numbers,
strings, arrays, and objects while retaining repeated values.

## Decision

Append `Sort` to the syntax and program discriminants so existing serialized
forms remain stable. Lower it as a zero-operand builtin and perform an
allocator-owned insertion sort using the existing `compare_values` ordering.
Every input element is transferred exactly once; unlike `unique`, equal
elements are retained.

## Consequences and limits

The change spans syntax, compiler, program, and evaluator. The verified slice
accepts arrays with mixed nested values and duplicates. Non-array diagnostics,
sort_by, and collation corner cases are deferred.

## Validation

`compat/sort.jq.test` is the focused oracle shard. Parser/compiler shape tests,
the pinned Odin build, and package tests must pass. The repository's existing
doctor pointer mismatch may still make `make validate` fail independently.
