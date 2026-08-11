# Decision 0158: bounded literal `range`

## Scope

Add an append-only `Range` AST/opcode for one-to-three numeric literal
arguments. The evaluator materializes the finite stream into an owned array and
uses the existing iterator continuation to emit each value.

## Evidence

The jq 1.8.1 cases at `upstream/jq/tests/jq.test:287-305,435-438` establish
half-open two- and three-argument behavior. `compat/range.jq.test` records
the supported positive-step cases against the pinned oracle.

## Deferred

Dynamic/comma-separated arguments, negative literal syntax, and control-flow
consumers such as `foreach`, `limit`, and `isempty(range(...))` remain deferred.
