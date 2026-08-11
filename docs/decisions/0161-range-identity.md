# Decision 0161: identity child for literal `range`

## Scope

Accept the standalone identity filter as the one-argument `range(.)` child.
The evaluator reads the numeric input as the exclusive end and reuses the
existing iterator-backed stream.

## Evidence

The jq 1.8.1 range consumers at `upstream/jq/tests/jq.test:397-405` exercise
`range(.)` with numeric inputs. The focused range shard records the identity
stream for input `3`.

## Deferred

Arbitrary dynamic expressions, generators, comma-separated arguments, and
non-numeric identity inputs remain deferred.
