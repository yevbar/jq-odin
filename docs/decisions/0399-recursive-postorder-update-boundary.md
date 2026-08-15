# Decision 0399: recursive post-order update remains deferred

Status: decision-only after an isolated probe from `c67bfc7e`.

## Target and probes

The jq.test:2093 query is:

```jq
(.. | select(type == "object" and has("b") and (.b | type) == "array")|.b) |= .[0]
```

Pinned jq 1.8.1 and a temporary AST lowering agree for the upstream input,
no-match object, `{}`, `null`, and `[]`:

```text
{"a":{"b":[1,{"b":3}]}}  -> {"a":{"b":1}}
{"a":{"c":1}}            -> {"a":{"c":1}}
{}                          -> {}
null                        -> null
[]                          -> []
```

The same lowering diverges on a nested matching array:

```text
input: {"b":[1,{"b":[2]}]}
jq:    Cannot index number with number (status 5)
lowering: {"b":1} (status 0)
```

The divergence is observable after a child update changes the recursive
descent stream; it is not a formatter or parser-only discrepancy.

## Source seam

The parser preserves the recursive selector as `Recurse | select(...) | .b`
(`src/syntax/parser.odin:1483-1488`, `src/syntax/parser.odin:1797-1815`),
while evaluator recursion emits child frames through `Recurse_Children`
(`src/eval/evaluator.odin:4189-4192`, `src/eval/evaluator.odin:12791-12825`).
The existing `walk(filter)` lowering (`src/syntax/parser.odin:6214-6284`)
is post-order but does not retain the original generated-path stream and its
mutation/error ordering. Replacing the selector with `walk(if ... then ... )`
therefore loses jq's path cardinality and typed late-error behavior.

## Required next contract

Implement a resumable recursive path-update frame that retains source paths,
applies each update against the original root in jq order, and propagates late
typed errors through `try`/error exits with explicit ownership. A route-only
walk substitution is unsafe; no source changes are retained in this lane.
