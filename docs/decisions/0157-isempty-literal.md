# Decision 0157: bounded `isempty` literal children

## Scope

Add the `isempty` AST/opcode and evaluator behavior for literal child filters.
The evaluator returns `true` for the `empty` child and `false` for scalar
literal children that emit one value.

## Evidence

The jq 1.8.1 behavior is anchored by `upstream/jq/tests/jq.test:2097-2101`.
This shard records the empty child and scalar cases against the pinned oracle.

## Deferred

Generator/dynamic children, error propagation, and assignment/continuation
forms remain deferred; in particular `isempty(range(3))` is not claimed.
