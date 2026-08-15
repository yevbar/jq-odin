# Decision 0389: recursive post-order update remains deferred

## Status

Decision-only; no source implementation is safe on the current update ABI.

## Evidence

jq.test:2093 is:

```jq
(.. | select(type == "object" and has("b") and (.b | type) == "array")|.b) |= .[0]
```

The pinned jq 1.8.1 oracle transforms
`{"a":{"b":[1,{"b":3}]}}` to `{"a":{"b":1}}`; nested matching objects
are updated in post-order, empty arrays become `null`, and no-match/scalar
roots remain unchanged. `null` and `[]` pass through unchanged. The current
candidate rejects the expression during parsing.

The assignment parser's bounded update admission handles literal Field/Index
trees and selected root iterator forms (`src/syntax/parser.odin:2975-3012`,
`3140-3226`); the target LHS is a recursive descent/Sequence/If/Field filter.
The evaluator's static update continuations retain one literal field/index
child (`src/eval/evaluator.odin:1370-1413`) and do not capture arbitrary
post-order path streams. Recursive descent and `select` already exist as read
filters, but no update frame retains child results while applying `.[0]` to
each selected path.

## Required contract

A sound implementation needs a resumable post-order traversal that snapshots
each object/array, evaluates the predicate and RHS per selected path, preserves
child-before-parent ordering, handles empty RHS/null synthesis, and keeps
ownership/error ordering under `try`. Parser admission or a textual rewrite
would lose traversal cardinality and nested update semantics; defer until that
shared continuation is designed and tested.
