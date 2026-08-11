# Decision 0116: bounded object-literal `contains`

`contains` now accepts static object and array literals. Object-subset checks
require every needle key and recursively compare nested values; arrays apply a
literal-element subset check. String-literal behavior is preserved. Dynamic
arguments and exact diagnostic wording remain deferred.

Evidence: `upstream/jq/tests/jq.test:1623-1625` and
`compat/contains-object-literal.jq.test` against the pinned oracle.
