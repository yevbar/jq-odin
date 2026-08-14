# Decision 0335: root iterator defined-or continuation

Status: proposed (2026-08-14)

## jq behavior

For root `.[] //= RHS`, jq updates only null and false values. Truthy values
pass through unchanged. The RHS runs with the original root input (for example,
`[null, 1] | .[] //= .[0]` reads the source array's first value), and path
assignment keeps only the first RHS output.

The focused compatibility shard is `compat/iterator-defined-or.jq.test`.

## Chosen design

Reuse `Static_Iterator_Update` with a defined-or marker in the existing
instruction metadata. On frame entry, clone the original root into the
parent-owned dynamic base. For each selected value, skip truthy values; for
null/false values, push the existing child continuation with a clone of the
saved root. Existing first-output cancellation and iterator cursor phases then
provide jq cardinality and resumability.

## Contract effects

The parser/compiler/evaluator packages are affected. The marker is included in
the evaluator program seal so tampering cannot silently alter dispatch. The
saved root and each child input are independently owned; skipped values are
destroyed before advancing, and the saved root is released with the parent
frame. Nested paths and non-root `//=` remain deferred.

Implementation evidence: `src/syntax/parser.odin:2656-2675`,
`src/compiler/package.odin:1323-1330`, and
`src/eval/evaluator.odin:361-369,8310-8317,10542-10566`.

## Review lanes

Request semantic-parity and Odin ownership/safety review, with focused probes
for null/false/truthy mixtures, root-valued RHS, multi-output RHS, and RHS
errors.
