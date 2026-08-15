# Decision 0388: generated map/select assignment remains deferred

## Status

Decision-only; no source implementation is safe on the current path ABI.

## Evidence

For jq.test:1273, the pinned jq 1.8.1 oracle reports the result-bearing
diagnostic for:

```jq
try ((map(select(.a == 1))[].b) = 10) catch .
```

With `[{"a":1}]`, the result is
`Invalid path expression near attempt to iterate through [{"a":1}]`; two
matching objects embed both objects, and an empty array embeds `[]`. `null`
and number roots retain typed `Cannot iterate over null/number` errors. The
candidate accepts the read filter `map(select(.a == 1))[].b` but rejects both
assignment forms at parse time.

The assignment parser's generated-path admission is limited to root Index,
Comma, or Call trees (`src/syntax/parser.odin:3452-3471`); this target is a
nested Field(Index(map/select), `b`) tree. The existing evaluator continuation
collects generated path children (`src/eval/evaluator.odin:8524-8560`) but does
not retain the intermediate mapped value needed for jq's result-bearing
diagnostic. Existing materialized map/select helpers are only diagnostic
bridges for `path(...)` (`src/eval/evaluator.odin:3103-3135`), not assignment
path streams.

## Required contract

A sound implementation needs a nested filter/index/field path continuation that
preserves intermediate values, detects iteration through those values before
mutation, formats the embedded JSON diagnostic, and retains ownership across
`try`/`catch`. Parser admission or textual rewriting would lose that contract;
defer until the shared continuation is designed and tested.
