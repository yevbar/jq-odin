# Odin CLI coverage snapshot

This is a coordinator snapshot for the accepted Odin CLI lineage, not a claim
of upstream jq compatibility. The immutable `upstream/jq` tree remains the
behavioral oracle.

## Current evidence

- Baseline integration head: `1a98ae1`.
- Static postfix indexing: `2e15478` (`.[N]` and `.field[N]`, literal
  non-negative integer bounds only).
- CLI diagnostic parity for string-key indexing: `f6babcc`; this preserves
  container-specific wording for non-numeric keys while leaving numeric-index
  errors on their bounded path.
- Bounded `atan`: `7a8135a`; its focused shard passes 1/1. The full catalog
  remains at 93/522 because jq’s unrounded floating-point text for the
  standalone `atan` case still differs from the candidate serializer.
- A sin/cos implementation was exercised and reverted (`294d9a6` / `9c9b873`)
  after its nonzero oracle shard exposed the same serializer mismatch
  (`cos(1)`); it remains a queued lane until native-number formatting is fixed.
- ASCII case transforms (`353bb2d`) and array-only `reverse` (`1d68db0`, with
  integration repairs in `43d1d46`) now pass their focused shards. The full
  catalog moved to 94/522 passing filters (428 remaining); the CLI harness
  reports 312 subprocess and 41 differential checks.
- Bounded ASCII `implode` (`932b819`) passes its focused shard and all package
  tests. It does not change the catalog total yet because the remaining core
  `implode` cases require Unicode code-point handling; that limitation is
  recorded in `compat/implode.md`.
- Bounded ASCII `explode` (`866a593`) also passes its focused shard and the
  full package suite. Its Unicode cases remain deferred, so the catalog is
  still 94/522; the implementation is intentionally not represented as full
  jq `explode` compatibility.
- `keys_unsorted` is now integrated at `1755567` with insertion-order object
  and array shards passing. The catalog remains 94/522 because its broader
  upstream cases still include unsupported surrounding filter forms.
- String-only `tostring` (`6ef3c6c`) passes its shard and all package tests;
  numeric, array, and object conversion remains deferred, so the catalog is
  still 94/522.
- Canonical `{key,value}` `from_entries` (`b6ff227`) passes its focused shard,
  package tests, and CLI smoke test. Alternate entry-key spellings and
  malformed/non-array diagnostics remain deferred; catalog coverage is still
  94/522.
- Canonical object `to_entries` (`80fe8a7`) passes its shard and package suite;
  the full catalog moved to 95/522 (427 remaining). Array/non-object forms
  remain deferred.
- Bounded `isnan` (`cb844b0`) passes its finite-number shard and package suite;
  the full catalog remains 95/522 because this parser snapshot cannot yet
  construct jq's `nan` literal, so positive-NaN and non-number diagnostic
  cases remain deferred.
- Bounded `not` (`a33cefa`) passes its truthiness shard and package suite;
  the full catalog is now 96/522 (426 remaining). Its zero-argument truthiness
  form is covered; generator and richer control-flow compositions remain
  deferred.
- Bounded `utf8bytelength` (`51d7b86`) passes its ASCII/UTF-8 shard and package
  suite; the full catalog is now 97/522 (425 remaining). Valid string values
  are covered, while typed non-string diagnostics and malformed UTF-8 remain
  deferred to a follow-up parity lane.
- Bounded zero-output `empty` (`1bf7a1b`) passes its generator/exhaustion shard
  and package suite; the full catalog is now 98/522 (424 remaining). Its
  zero-argument form is covered; argument-bearing and richer control-flow
  combinations remain deferred.
- Bounded `values` (`d3ec1bd`) passes null suppression and scalar passthrough
  shards with the full package suite; the full catalog is now 99/522 (423
  remaining). Object/array stream compositions and richer argument forms are
  still deferred.
- Package validation and the full Odin package test suite pass on the
  integration worktree. The CLI harness reports 311 subprocess checks and 40
  differential checks.
- The jq catalog moved from 90/522 passing filters at the baseline to 93/522
  after static indexing; 429 catalog cases still fail. The catalog report is
  generated with `tools/compat/catalog_report.py` and is intentionally kept as
  an external artifact rather than committed output.
- The focused postfix-index shard passes 5/5 against the pinned jq oracle;
  see `compat/postfix-index.md` and decision `0066`.

## Remaining high-value clusters

The largest remaining groups are not all independent builtins. They include
dynamic indexes and slices, path mutation/assignment, richer binding and
module forms, generator/control-flow combinations, and process/codec APIs.
These need separate AST/program/evaluator contracts rather than parser-only
patches. In particular, dynamic indexes and assignment must establish value
path ownership before they are parallelized; otherwise lanes can appear to
pass isolated syntax tests while corrupting evaluator state.

## Repeating the measurement

Build the candidate with the pinned Odin toolchain, run the package checks and
CLI harness, then run the full catalog. Every new lane should add a focused
`compat/*.jq.test`, an explicit skip manifest for unsupported cases, and a
decision/evidence note with `path:line` citations. Review lanes should compare
only the merge-base-to-head diff and attempt to falsify the focused shard
before integration.
