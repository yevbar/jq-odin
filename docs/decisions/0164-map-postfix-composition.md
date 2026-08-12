# Decision 0164: map postfix composition

The parser permits `map` child filters to contain comma-separated generators,
and recognizes the jq dotted optional iterator spelling `.a.[]?` as the same
postfix array iteration used by `.a[]?`. This is a syntax-only extension over
existing `Map`, `Optional`, `Field`, and `Index` evaluator contracts.

Oracle evidence: `upstream/jq/tests/jq.test:200`.

Dynamic generators, assignments, and broader map/control-flow forms remain
deferred.
