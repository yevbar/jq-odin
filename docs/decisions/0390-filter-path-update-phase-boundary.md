# Decision 0390: Filter_Path_Update remains deferred

## Status

Decision-only on 79b61adb; no parser/program/evaluator source change.

## Evidence

jq.test:1277 is:

```jq
try ((map(select(.a == 1))[].a) |= .+1) catch .
```

Pinned jq 1.8.1 reports `Invalid path expression near attempt to iterate
through [{"a":1}]` for `[{"a":0},{"a":1}]`, embeds both matching
objects for two matches, and embeds `[]` for an empty array. Null and number
roots retain `Cannot iterate over null/number` diagnostics. The Odin candidate
still rejects the assignment at parse time, while the read filter
`map(select(.a == 1))[].a` is accepted.

The exact LHS is a nested Field over an iterator over a Map/Select filter;
the parser's generated assignment admission only accepts root Index, Comma,
or Call trees (`src/syntax/parser.odin:3452-3471`). Existing evaluator
`Path_Assign` collection (`src/eval/evaluator.odin:8524-8560`) has no state for
the intermediate map value needed by jq's result-bearing diagnostic, and the
static field update frames cannot apply a filter-valued RHS to each generated
path while preserving `|=` cardinality.

## Required contract

An implementation needs an append-only Filter_Path_Update form carrying the
nested path filter and RHS, with resumable capture of intermediate values,
typed invalid-path formatting, copy-on-write application, and try/catch-safe
ownership. Parser admission or a textual rewrite would either lose the
embedded diagnostic or mutate a temporary map rather than the original input.
