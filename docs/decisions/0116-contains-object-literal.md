# Decision 0116: bounded object-literal `contains`

`contains` now accepts static object literals and applies jq's shallow
object-subset rule: every needle key must be present in the input and each
value must compare equal (or recursively contain where a nested literal is
available). String-literal behavior is preserved. Dynamic, array-literal,
nested, and diagnostic forms remain deferred.

Evidence: `upstream/jq/tests/jq.test:1623-1625` and
`compat/contains-object-literal.jq.test` against the pinned oracle.
