# `add(empty)` compatibility shard

This lane accepts literal `empty` and numeric `range` generators as the child
of `add`. Empty streams return `null`; emitted values are reduced in order.
The standalone identity-bound `range(.)` form is also supported. Child filters
that already produce streams, such as `.[]` and parenthesized literal ranges,
reuse the same accumulator. Null and map-produced streams are covered as well;
other dynamic arguments remain deferred.

Comma-separated child streams are also reduced as one stream. Literal
one-argument nested ranges such as `range(range(10))` are expanded in the
existing range evaluator; arbitrary higher-order generators remain deferred.

Identity bounds in multi-argument `range` forms are also covered when they use
the current numeric input.

Evidence: jq defines `add` by reducing its input in `upstream/jq/src/builtin.jq:57`;
the empty-generator behavior is exercised by the pinned jq oracle.
