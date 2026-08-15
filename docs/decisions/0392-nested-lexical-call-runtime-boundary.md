# Decision 0391: nested lexical call runtime remains deferred

## Status

Structural parser/compiler evidence added; runtime activation remains deferred.

## Evidence

jq.test:864 is:

```jq
def id(x):x; 2000 as $x | def f(x):1 as $x | id([$x, x, x]); def g(x): 100 as $x | f($x,$x+x); g($x)
```

The pinned jq 1.8.1 oracle emits `"more testing"` followed by
`[1,100,2100.0,100,2100.0]`. The current CLI path still crashes before
producing output; the parser alone successfully records three definitions with
ordinals 0, 1, 2, nested scope depths for `f`/`g`, and formal references
distinct from lexical `$x` variables.

Focused structural tests now pin that exact definition table and the lowered
outer Binding's three instruction/text edges (`src/syntax/parser_test.odin`
and `src/compiler/compiler_test.odin`). No evaluator route is added.

## Required runtime contract

Correct execution needs definition-table lookup plus lexical call frames that
retain each caller's bindings, formal filter closures, generator cardinality,
and nested definition snapshots. The existing one-formal closure frame cannot
route this multi-definition graph without reusing shadowed `$x` values or
losing `f($x,$x+x)` stream cardinality. Textual expansion is unsafe because it
changes closure scope and recursive call ownership.
