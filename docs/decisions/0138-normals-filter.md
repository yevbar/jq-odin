# Decision 0138: normal-number type filter

The `normals` builtin uses an append-only syntax and program discriminant.
The evaluator forwards a number only when it is neither NaN nor infinite and
its absolute value is at least `2.2250738585072014e-308`, the IEEE-754 binary64
minimum normal magnitude. Zero and subnormals are therefore suppressed, as
are all non-number values.

This mirrors jq's `normals: select(isnormal)` definition without new package
edges or shared value contracts. Dynamic generators and diagnostics remain
deferred.
