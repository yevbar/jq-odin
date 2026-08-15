# Decision 0348: first-class post-order `walk(filter)` contract

## Status

Deferred pending a shared syntax/program/evaluator vertical slice.

## Evidence

The jq definition in `upstream/jq/src/builtin.jq:212-221` recursively visits
arrays and objects before applying the callback. Arrays retain every callback
result (`map(w)`), while objects use `map_values(w)` semantics (delete on an
empty result and retain the first result for a multi-result callback). The
catalog case at `upstream/jq/tests/jq.test:2385-2390` uses
`walk(select(IN({}, []) | not))` and returns `{"a":1}` for
`{"a":1,"b":[]}`.

## Current boundary

The Odin parser has no `walk` node or filter-valued call production; the
driver bridge only rewrites literal `walk(.)` forms. Existing `Map` frames are
one-level and cannot represent post-order recursion, container rebuilding, or
the different array/object cardinality rules. A textual rewrite would silently
change callback ordering and error behavior.

## Required contract

Add an append-only `Walk` AST/program form with one filter child. The evaluator
must own a resumable post-order frame containing the current container kind,
cursor, rebuilt container, and callback stream state. It must preserve key
order, propagate callback errors and resource failures, and distinguish array
multi-output from object first-output/empty deletion semantics. Focused tests
must cover empty containers, root callbacks, multi-output callbacks, and late
errors before enabling the catalog case.
