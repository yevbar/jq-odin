# 0096: Add bounded literal index family

- Status: accepted
- Workstream: syntax/compiler/evaluator

## Context and evidence

jq's literal search cases are at
`upstream/jq/tests/jq.test:1515-1521`, `1555-1557`, and `1559-1571`.

## Decision

Append `Index_Builtin`, `Rindex_Builtin`, and `Indices_Builtin` syntax/program
discriminants. Parse each one literal string argument, lower one instruction
edge, and evaluate string input with first, last, or overlapping occurrence
search respectively. Convert string matches from UTF-8 byte offsets to Unicode
code-point offsets, matching jq. Preserve jq's input-kind behavior for this
literal form:
null returns null for all three; array input compares exact string elements,
returning first/last matching indexes or all matching indexes.

## Consequences and limits

This lane avoids a general function-call contract. Empty needles, two-argument
forms, array needles, dynamic arguments, and non-string diagnostics are
explicitly deferred. Array inputs are supported only for literal string
needles; array needles remain deferred.

## Validation

Run the focused compatibility shard against pinned jq and the Odin candidate,
the pinned Odin build, parser/compiler/evaluator tests, and `make validate`.
