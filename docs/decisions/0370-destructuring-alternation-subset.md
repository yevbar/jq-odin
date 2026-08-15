# Decision 0370: same-name destructuring alternation subset

## Status

Implemented on `agent/language/destructuring-alternation-subset` as a bounded
syntax lowering that reuses existing `Try` and `Binding` instructions.

## Contract

The parser accepts exactly three same-name alternatives in either of these
bounded orders, with one field and one repeated variable name:

```jq
. as {a:$a} ?// {a:$a} ?// $a | BODY
. as {a:$a} ?// $a ?// {a:$a} | BODY
```

The producer is captured once by an outer binding. Each projection and scalar
fallback is represented as nested `Try` children, preserving jq's behavior that
a branch's later body errors can advance to the next alternative. Scalar
fallback branches are explicitly piped through the captured value so `BODY`
receives the original input rather than a caught error value.

The guard intentionally excludes multiple fields, differing variable names,
array/object mixed alternatives, scalar-first permutations, and arbitrary
alternative counts. Those forms still require a first-class Alternation AST/IR
continuation with branch scope rollback and generator cardinality.

## Evidence

Oracle source cases are `upstream/jq/tests/jq.test:952`, `:959`, `:966`,
`:973`, `:980`, `:987`, `:994`, and `:1001`. Focused fixture
`compat/destructuring-alternation-subset.jq.test` covers mixed object, array,
scalar, and null inputs, original-body input preservation, and a body error
that must not trigger a later alternative.

The lowering uses the existing Binding evaluator continuation
(`src/eval/evaluator.odin:4940-4965`) and Try continuation
(`src/eval/evaluator.odin:10724-10729`, `:4308-4313`). No new package or opcode
was added. `src/syntax/parser_test.odin` asserts the nested Binding/Try shape.
