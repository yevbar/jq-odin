# Decision 0262: bounded literal `delpaths`

## Context

The evaluator already owns copy-on-write path lookup and `setpath` updates,
but `delpaths` was parsed as an unsupported builtin. jq accepts an array of
path arrays and deletes each path in order; object misses are no-ops and array
deletions remove an element, shifting later indexes.

## Decision

Add a `Delpaths` syntax node and program opcode. The first implementation is
explicitly bounded to a literal outer array whose path members contain only
literal string and integer components (with parser fork/sequence flattening
for comma-separated members). The evaluator applies each path sequentially to
an owned copy of the input, rebuilding arrays on deletion and using the value
package's copy-on-write object deletion primitive. An empty path yields `null`.

Dynamic path streams, non-literal components, and richer jq runtime diagnostics
remain follow-up contracts rather than being silently interpreted as literals.

## Ownership and package impact

`src/syntax` owns the node and parser spelling; `src/program` and
`src/compiler` own the opcode and lowering metadata; `src/eval` owns path
deletion and allocator cleanup. No package graph edges or shared public value
contracts change.
