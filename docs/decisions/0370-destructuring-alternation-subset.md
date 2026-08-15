# Decision 0370: same-name destructuring alternation subset

## Status

Implemented on `agent/language/destructuring-alternation-subset` as a bounded
syntax lowering that reuses existing `Try` and `Binding` instructions.

## Contract

The parser accepts exactly two object alternatives followed by a scalar
fallback, with one field and one repeated variable name:

```jq
. as {a:$a} ?// {a:$a} ?// $a | BODY
```

The producer is captured once by an outer binding. Each object projection and
the fallback variable are represented as nested `Try` children, preserving jq's
behavior that a branch's later body errors can advance to the next alternative.
The fallback path is explicitly piped through the captured value so `BODY`
receives the original input rather than the caught error value.

The guard intentionally excludes multiple fields, differing variable names,
array/object mixed alternatives, and arbitrary alternative counts. Those forms
still require a first-class Alternation AST/IR continuation with branch scope
rollback and generator cardinality.

## Evidence

Oracle source cases are `upstream/jq/tests/jq.test:952` and `:959`. Focused
fixture `compat/destructuring-alternation-subset.jq.test` covers mixed object,
array, scalar, and null inputs, original-body input preservation, and a body
error that must not trigger a later alternative.

The lowering uses the existing Binding evaluator continuation
(`src/eval/evaluator.odin:4940-4965`) and Try continuation
(`src/eval/evaluator.odin:10724-10729`, `:4308-4313`). No new package or opcode
was added. `src/syntax/parser_test.odin` asserts the nested Binding/Try shape.
