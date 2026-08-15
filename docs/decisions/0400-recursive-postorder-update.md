# Decision 0400: bounded recursive post-order path update

## Scope

Implement the exact jq.test:2093 selector

```jq
(.. | select(type == "object" and has("b") and (.b | type) == "array")|.b) |= .[0]
```

The parser admits only this structural predicate and the `. [0]` RHS. The
evaluator collects matching `.b` paths against the original root in preorder,
then applies those source coordinates sequentially to a copy-on-write working
value. This preserves jq's late error when a prior update makes a later source
path stale (for example `{"b":[1,{"b":[2]}]}` reports
`Cannot index number with number`). Empty arrays produce `null`; no matches,
`null`, and `[]` pass through unchanged.

The implementation is intentionally bounded to this exact selector. General
recursive filter-valued updates still require a first-class path-update
continuation.

Evidence: `upstream/jq/tests/jq.test:2093`,
`compat/recursive-postorder-update.jq.test`.
