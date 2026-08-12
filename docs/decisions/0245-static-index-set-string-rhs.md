# Decision 0245: string RHS for static assignment

Static field/index assignment now accepts quoted string literals. The compiler
prefixes the owned string payload with an internal marker so evaluator lowering
cannot confuse a string such as `"true"` with a boolean marker. Dynamic RHS
filters, containers, and nested paths remain deferred.

Oracle evidence: `compat/static-index-set.jq.test` and
`upstream/jq/tests/jq.test:221-229`.
