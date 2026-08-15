# Decision 0356: bounded generated-path assignment

## Status

Accepted for the `=` form with literal numeric/field path filters and
arbitrary RHS streams. The implementation is intentionally separate from
`|=` and from dynamic path components.

## Contract

`Path_Assign` owns two child instructions. It collects path arrays in source
order, evaluates the RHS once against the original input, and applies each RHS
output copy-on-write to every collected path. Empty RHS streams emit no roots;
each RHS output produces one updated root. Path application preserves catchable
`Cannot index KIND with number/string` diagnostics and null synthesis.

The path collector recognizes literal numeric/field paths, comma streams, and
zero-argument definitions wrapping those paths. The evaluator stores owned path
and RHS arrays on the assignment frame and releases them on every frame-unwind
path. Late RHS errors after a prior output and empty path-generator validation
remain deferred; the bounded slice does not claim those semantics yet.

## Boundary

`|=` selected-value updates, dynamic path components, empty path-generator
validation, late RHS errors after a prior output, overlapping-path conflict
rules beyond sequential copy-on-write, and general path-valued LHS filters are
deferred until a shared path-update continuation contract is available.

## Evidence

The focused fixture `compat/path-assignment-generated.jq.test` compares direct
and callable paths, empty/multi-output RHS streams, null synthesis, and typed
scalar/object failures against the pinned jq 1.8.1 oracle. The source
catalog target is `upstream/jq/tests/jq.test:1281`.
