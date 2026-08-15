# Decision 0357: preserve generated-path invalid-result diagnostics

## Status

Accepted for the bounded `=` generated-path case represented by
`try (def x: reverse; x=10) catch .`. This extends decision 0356's
generated-path assignment frame without broadening the path-update ABI.

## Contract

When `Path_Assign` receives a non-literal path filter, it evaluates that
filter directly on the assignment input and owns the resulting path stream.
Generated results are not literal path syntax, so the evaluator raises the
catchable jq diagnostic `Invalid path expression with result VALUE` for each
generated result, where `VALUE` is its compact JSON representation. This
includes scalar and array results that might otherwise look indexable.
Literal numeric/field paths continue through their existing materialized path
route and retain typed root/container diagnostics.

## Boundary

This slice does not change `|=` updates, dynamic path-component coercion,
path stream cardinality, or general path-valued LHS behavior. Literal
numeric/field syntax remains the only generated-path success route; other
path-valued LHS forms remain deferred until a broader path-update continuation
contract is available.

## Evidence

The source case is `upstream/jq/tests/jq.test:1285`:
`try (def x: reverse; x=10) catch .` over `[0,1,2]` yields
`"Invalid path expression with result [2,1,0]"` under jq 1.8.1. The focused
fixture `compat/path-assignment-generated.jq.test` records this output and a
literal-path regression, while the driver test exercises both through the
compiled evaluator. The implementation is confined to the existing
`Path_Assign` frame and does not rewrite source text or alter the shared path
ABI.
