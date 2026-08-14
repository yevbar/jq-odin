# Decision 0329: optional and try update RHS require path-update continuations

## Evidence

The jq 1.8.1 cases at `upstream/jq/tests/jq.test:2335` and `:2348` cover
`.foo |= .?` and `.[] |= try tonumber`. The pinned probes are recorded in
`compat/optional-update-boundary.md`: optional identity creates a missing field
as null and materializes null input as an object; `try tonumber` emits only
successful numeric conversions while suppressing per-element errors and
deleting empty results.

## Existing-IR boundary

`Dynamic_Field_Set` accepts identity, one field, or literal RHS instructions,
but its identity path evaluates against the whole frame input
(`src/eval/evaluator.odin:8103-8133`), not the selected field. Reusing it for
`.foo |= .?` would therefore write the whole object into `foo`, violating jq's
selected-value semantics. `Setpath` is limited to literal path/replacement
operands (`src/eval/evaluator.odin:7470-7490`). The iterator delete opcode has
no RHS continuation and cannot represent `try tonumber` streams.

## Decision

Do not add a parser-only alias or textual rewrite. A correct implementation
needs a first-class path-update continuation that captures each selected value,
runs an RHS filter with zero/one/many outputs and caught errors, then applies
copy-on-write replacement/deletion. `.foo |= .?` can be a later bounded slice
once that contract exists; `.[] |= try tonumber` should follow it rather than
introduce a one-off evaluator path.
