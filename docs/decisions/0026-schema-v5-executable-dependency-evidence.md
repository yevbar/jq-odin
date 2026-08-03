# Schema-v5 executable dependency evidence

## Status

Accepted for the compat workstream process adapter on 2026-08-03.

## Context

The process adapter recursively seals `$ORIGIN` dependencies and executes those
sealed bytes, but schema-v5 reports previously exposed identity evidence only
for the top-level image and optional shebang interpreter. Artifact review could
not determine which recursive dependency bytes were used.

## Decision

The schema-v5 `oracle` and `candidate` executable identity objects add a
`dependencies` array. Each entry contains the deterministic absolute capture
path, SHA-256 of the sealed bytes, and captured source device and inode. Entries
are sorted by path. A native shebang interpreter's nested `interpreter` object
has the same additive `dependencies` array. Scripts have an empty top-level
array because their ELF dependencies belong to the separately captured native
interpreter.

The report schema remains version 5. Existing schema-v5 fields retain their
meaning and representation, and readers that accept additive object fields
remain compatible. This change exposes evidence already retained by the
adapter; it exposes neither live file contents, secrets from neighboring paths,
nor process-local descriptor numbers.

## Producers and consumers

The compat workstream is both producer and direct consumer. The producer is
`tools/compat/shtest_compat.py`; its direct report tests and the compatibility
documentation are updated with the field. No Odin package, fixture schema,
root command, package edge, or jq case meaning changes.

## Consequences

Reports can now prove exactly which recursively captured `$ORIGIN` images were
used by a top-level ELF executable or native shebang interpreter. Exact-key
schema-v5 consumers must accept the additive field, while value consumers can
compare its stable path order and captured identities directly.

The adapter owns every captured dependency descriptor until its
`ExecutableImage` is closed. Report dictionaries own copied scalar path, hash,
device, and inode values only; no descriptor or borrowed live-path authority
escapes into the report.

## Rejected alternatives

- Incrementing the schema version was rejected because no existing field is
  removed, renamed, or reinterpreted.
- Reporting descriptor numbers was rejected because they are process-local,
  unstable, and reveal authority that consumers neither need nor can validate.
- Reporting directory contents was rejected because it could expose unrelated
  live material and would exceed the bounded executable-capture contract.

## Compatibility and review evidence

Focused native and shebang tests compile recursive `$ORIGIN/../lib` fixtures
and compare the exact path-sorted identity arrays, including SHA-256 and source
device/inode. Full process-adapter, compatibility-discovery, core-catalog,
process-catalog, and root validation remain required.

Adversarial review should independently check recursive ordering, duplicate
dependency handling, native-versus-script placement, early-failure empty
arrays, absence of descriptors/live contents, and tolerance by additive-field
schema-v5 consumers.
