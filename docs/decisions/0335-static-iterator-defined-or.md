# Decision 0335: root iterator defined-or continuation

Status: proposed (2026-08-14)

## jq behavior

For root `.[] //= RHS`, jq updates only null and false values. Truthy values
pass through unchanged in every emitted root. The RHS runs once with the
original root input (for example, `[null, 1] | .[] //= .[0]` reads the source
array's first value), and each RHS output emits an independent root. An empty
RHS emits no root.

The focused compatibility shard is `compat/iterator-defined-or.jq.test`.

## Chosen design

Reuse `Static_Iterator_Update` with a defined-or marker in the existing
instruction metadata. On frame entry, clone the original root into the
parent-owned dynamic base and launch one child continuation. For each child
output, clone the original root and apply that output to all null/false values;
truthy values remain unchanged. The child is allowed to exhaust naturally so
later outputs and errors remain observable; an empty child produces no root.

## Contract effects

The parser/compiler/evaluator packages are affected. The marker is included in
the evaluator program seal so tampering cannot silently alter dispatch. The
saved root and each child input are independently owned; skipped values are
destroyed before advancing, and the saved root is released with the parent
frame. Nested paths and non-root `//=` remain deferred.

Implementation evidence: `src/syntax/parser.odin:2656-2675`,
`src/compiler/package.odin:1323-1330`, and
`src/eval/evaluator.odin:361-369,8397-8438,10640-10670`.

## Review lanes

Request semantic-parity and Odin ownership/safety review, with focused probes
for null/false/truthy mixtures, root-valued RHS, multi-output RHS, and RHS
errors.
