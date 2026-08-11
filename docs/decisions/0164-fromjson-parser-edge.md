# Decision 0164: let `fromjson` use the JSON parser

## Scope

Allow the `eval` package to import `jq:json` and delegate zero-argument
`fromjson` text parsing to `json.parse_value`. This extends the previous
scalar-only slice to arrays, objects, strings, and nested JSON values while
preserving parser ownership of the returned `Value`.

## Evidence

The focused `compat/fromjson-values.jq.test` shard compares structured values
and a `tojson | fromjson` round trip against pinned jq 1.8.1. The existing JSON
parser is the implementation source for the new package edge.

## Deferred

Exact jq parse-error wording, dynamic `fromjson` arguments, and module-specific
JSON behavior remain deferred.
