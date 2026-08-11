# Decision 0190: bounded `any(not)` and `all(not)`

## Scope

Support the literal `any(not)` and `all(not)` forms over array input. The
evaluator computes the negated truthiness aggregate directly, preserving jq's
empty-array identities without introducing a generator continuation.

## Evidence

The direct jq 1.8.1 cases at `upstream/jq/tests/jq.test:1061-1073` establish
the empty, false, and true array behavior.

## Deferred

Parameterized generators, condition expressions, and non-array diagnostics
remain deferred.
