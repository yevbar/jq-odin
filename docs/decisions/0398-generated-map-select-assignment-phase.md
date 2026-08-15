# Decision 0398: bounded generated map/select assignment phase

Status: source phase on integration `49f85162`; limited to jq.test:1273/1277.

## Accepted shape

The parser admits exactly `map(select(.a == 1))[].b = 10` and
`map(select(.a == 1))[].a |= .+1` when wrapped by the upstream `try ... catch`
queries.  The AST is a `Path_Assign` whose path is `Field(Field(Map(If(Equal(Field, Number)))))`;
the empty inner field is the iterator.  Other filter-valued paths remain
parse errors and do not enter this continuation.

## Runtime contract

Before evaluating either RHS, the evaluator materializes the root map/select
result into an owned array of matching objects.  It then reports jq's typed
invalid-path diagnostic (`Invalid path expression near attempt to iterate
through VALUE`) for array/object roots.  Null, number, boolean, and string roots
use the existing `Cannot iterate over TYPE (VALUE)` runtime transport.  The
materialized array and generated error key are destroyed on both normal and
`try`/catch paths; no input mutation occurs.

Pinned jq 1.8.1 and the candidate agree for `[ {"a":0}, {"a":1} ]`,
`[{"a":1}]`, `[]`, `{}`, `null`, `1`, `true`, and `"x"` for both operators.

## Scope boundary

This is not a general filter-path continuation: arbitrary predicates, nested
prefixes, dynamic postfixes, and successful generated-path mutation remain
deferred.  The strict syntax guard and evaluator shape check must remain in
lockstep before widening the ABI.
