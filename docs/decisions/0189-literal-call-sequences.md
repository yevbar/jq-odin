# Decision 0189: literal variadic `join` and `flatten`

## Scope

Lower comma-separated literal calls such as `join(",","/")` and
`flatten(3,2,1)` into ordinary comma sequences of the existing one-argument
operations. This adds jq's multiple-output behavior without introducing a new
evaluator continuation or ownership contract.

## Evidence

The jq 1.8.1 cases at `upstream/jq/tests/jq.test:445` and
`upstream/jq/tests/jq.test:455` establish the separator and depth sequences.

## Deferred

Dynamic arguments, generator-valued calls, and non-literal separator/depth
diagnostics remain deferred.
