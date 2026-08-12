# Decision 0238: static scalar literals for `in` and `inside`

Allow `inside(...)` to parse static JSON scalar arguments in addition to its
existing array/object literals. The evaluator already lowers these forms to
the shared `contains_result` kernel, where scalar values compare by jq value
equality and strings use substring containment. `in(...)` remains restricted
to array/object arguments because its `has_result` contract reports a typed
error for scalar containers. Dynamic expressions and generator-valued
arguments remain outside this lane because they require continuation and
value-stream contracts.

The parser change is intentionally limited to literal `null`, booleans,
numbers, strings, and `nan`; AST/program discriminants and evaluator ownership
are unchanged.
