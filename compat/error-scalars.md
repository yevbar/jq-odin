# Scalar `error` literals compatibility shard

`error(...)` accepts static number, boolean, and null literals. A caught error
returns the typed scalar value, while an uncaught error uses the compact JSON
rendering as its diagnostic key. Dynamic expressions and object/array error
arguments remain deferred.

The upstream oracle cases are `upstream/jq/tests/jq.test:1447-1451`.
