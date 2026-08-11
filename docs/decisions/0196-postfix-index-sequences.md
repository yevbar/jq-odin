# Decision 0196: comma-separated postfix index reads

The parser accepts a bounded comma-separated sequence of signed integer
literals inside postfix brackets, such as `.[-2,0,1]`. Each literal is lowered
to the existing `Index` node and combined with the existing `Comma` stream
operator, so the evaluator emits one result per requested index while
preserving null for out-of-range positions.

This extends the existing static postfix-index slice without adding a new
continuation or ownership contract. Dynamic expressions, slices, floating
point indexes, and assignment/update forms remain deferred. The behavior is
grounded in `upstream/jq/tests/jq.test:283-285`.
