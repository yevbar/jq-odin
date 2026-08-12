# Decision 0203: bare `error` filter

The parser now lowers bare `error` to a current-input message while retaining
the existing owned runtime-error path. This enables suppression by `limit(0;
error)` and direct diagnostics without introducing a second diagnostic contract.
Dynamic error arguments, non-string coercion edge cases, `halt`, and `debug`
remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:365,373,1447-1482`.
