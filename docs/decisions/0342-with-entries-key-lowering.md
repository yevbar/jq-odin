# Decision 0342: bounded `with_entries` key-prefix lowering

## Scope

Recognize `with_entries(filter)` and lower it to the existing
`to_entries | map(filter) | from_entries` AST pipeline. The current vertical
slice accepts the existing static object-entry update
`.key |= "KEY_" + .`, which exercises real parser, compiler, Map, and
entry-materialization paths rather than a driver text rewrite.

## Evidence

The focused `compat/with-entries-key.jq.test` shard passes the selected
object/composition/empty-object cases against jq 1.8.1. Existing `To_Entries`,
`Map`, and `From_Entries` instructions provide the runtime pipeline; the
bounded field update already owns copy-on-write key replacement.

Scalar/non-object diagnostics, arbitrary filter-valued entry updates,
generator RHS cardinality, and dynamic entry paths remain deferred until the
generic path-update continuation contract is implemented.
