# Decision 0160: unary-negative literal `range` operands

## Scope

Extend the bounded literal `range` lane to accept parser-owned unary-negative
number literals as start, end, or step operands. Existing iterator-backed
streaming and ownership remain unchanged.

## Evidence

The jq 1.8.1 cases at `upstream/jq/tests/jq.test:299-305` establish descending
half-open ranges. The focused range shard records empty descending mismatch and
the `0,-1,-2,-3,-4` stream.

## Deferred

Dynamic arithmetic, comma-separated generators, and control-flow consumers
remain deferred.
