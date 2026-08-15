# Decision 0346: bounded `JOIN($idx; idx_expr)` lowering

The parser accepts the two-argument uppercase jq builtin `JOIN($idx;
idx_expr)` only when `$idx` is a static object literal. It lowers the jq
definition

```jq
[.[] | [., $idx[idx_expr]]]
```

to the existing `Map`, array-constructor, and dynamic `Index` instruction
contracts. This is a real AST lowering; no driver or textual rewrite is used.

The focused shard `compat/join-index.jq.test` covers upstream
`upstream/jq/tests/jq.test:2051`. `JOIN/3` and `JOIN/4`, dynamic index objects,
and generator-valued index expressions remain deferred because they require a
resumable multi-operand JOIN frame and explicit ownership for source/key
streams.
