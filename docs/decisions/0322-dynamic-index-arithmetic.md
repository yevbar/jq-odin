# Bounded arithmetic dynamic-index keys

The postfix dynamic-index parser accepts a bounded binary key beginning with
the immediate identity, such as `[. + 0]`, `[. - 1]`, or `[. * 2]`. It lowers
the key to the existing `Binary` syntax node and `Index` instruction ABI; the
existing evaluator continuation therefore retains input ownership and stream
semantics. The right operand is parsed normally through the closing bracket.
Parenthesized/filter-valued keys and other dynamic-key forms remain deferred.

Evidence: `compat/dynamic-index-arithmetic.jq.test` matches the pinned jq
oracle; numeric and immediate-identity dynamic indexes remain unchanged.
