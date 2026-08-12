# Decision 0254: bounded dynamic arithmetic range bounds

Evaluate a static expression tree containing identity, numeric literals,
unary negation, parentheses, and `+`, `-`, or `*` directly against the current
input. This avoids adding a continuation frame while covering one numeric
result per bound. Generator-valued bounds, division/modulo, and arbitrary
dynamic filters remain deferred.
