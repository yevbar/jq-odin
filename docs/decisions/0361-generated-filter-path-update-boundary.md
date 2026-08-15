# Decision 0361: generated filter path update boundary

Status: audited and deferred from integration `3d3ffc13`.

The jq.test:1277 expression
`try ((map(select(.a == 1))[].a) |= .+1) catch .` is not a safe extension of
the current bounded path-assignment ABI. Pinned jq 1.8.1 reports a
result-bearing path diagnostic, not a parser failure:

```text
"Invalid path expression near attempt to iterate through [{\"a\":1}]"
```

For two matching elements the embedded value changes to
`[{"a":1},{"a":1}]`; for an empty input it is `[]`. The current candidate
rejects all three forms at parse time, although the read filters
`map(select(.a == 1))[].a` are accepted and produce the expected values.

Evidence:

- `upstream/jq/tests/jq.test:1277-1279` is the compatibility target and
  captures the required caught diagnostic.
- `src/syntax/parser.odin:3233-3250` lowers generated `Path_Assign` only when
  the assignment LHS is a root `Index`, `Comma`, or `Call`; the target's LHS is
  a `Field(Index(Call(map), []), a)` tree.
- `src/eval/evaluator.odin:8358-8394` evaluates generated path children and
  `src/eval/evaluator.odin:4683-4708` rejects non-array path results. Those
  continuations do not retain the intermediate `map(...)` value needed to
  render jq's “near attempt to iterate through” diagnostic.

A correct implementation requires a new path-capture contract for nested
filter/index/field chains: preserve the intermediate filter result, detect
iteration through that non-root value before mutation, format its value in the
typed runtime diagnostic, and retain ownership across `try`/`catch`. A parser
special case or textual rewrite would either lose the result-bearing error or
mistakenly mutate the mapped temporary array. Defer until that shared
continuation contract is designed and tested.
