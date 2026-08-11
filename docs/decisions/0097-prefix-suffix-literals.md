# Decision 0097: bounded literal `startswith` and `endswith`

Implement `startswith("literal")` and `endswith("literal")` as operand-bearing
filters with appended AST and program discriminants. Both require string input
and return a boolean; empty literals match every string. Dynamic arguments,
non-string coercions, and generator forms remain deferred.

The focused compatibility evidence is in `compat/prefix-suffix.jq.test` and
tracks jq's builtin definitions in `upstream/jq/src/builtin.c:1922-1927` and
the source cases at `upstream/jq/tests/jq.test:1487-1491`.
