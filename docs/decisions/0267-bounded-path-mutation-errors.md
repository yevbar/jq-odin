# Bounded path-mutation runtime errors

## Decision

Literal `delpaths/1` and `setpath/2` failures in the initial evaluator should
raise a resumable `Runtime_Error` with jq's diagnostic text, allowing
`try ... catch` to observe the same string. This slice handles a non-array
`delpaths` argument and a numeric `setpath` component applied to an object.

## Evidence

- `upstream/jq/tests/jq.test:1164-1167` — `try delpaths(0) catch .` yields
  `"Paths must be specified as an array"`.
- `upstream/jq/tests/jq.test:2452-2454` — invalid numeric `setpath` yields
  `"Cannot index object with number"` through `try ... catch`.

The broader dynamic path and nested mutation error taxonomy remains deferred
until the evaluator's resumable path contract is expanded.
