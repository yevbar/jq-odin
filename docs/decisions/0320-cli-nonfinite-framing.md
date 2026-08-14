# CLI framing for payload-free nonfinite JSON numbers

Status: implemented as a bounded command-line framer extension from
integration commit `f8fee371`.

The framer now recognizes exactly `Infinity`, `-Infinity`, `NaN`, and `-NaN`
as complete scalar tokens. It retains delimiter validation, so suffixes such as
`Infinity0` and `NaN1` are rejected before the value parser is invoked. Existing
lowercase `nan` and JSON literals remain unchanged; arbitrary NaN payloads are
not broadened.

Evidence:

- `cmd/jq-odin/main.odin:510-548` defines the scalar states and fixed literal
  storage used by the framer.
- `cmd/jq-odin/main.odin:675-711` starts exact uppercase special literals and
  keeps ordinary numeric/literal states separate.
- `cmd/jq-odin/main.odin:808-850` validates each literal byte and only returns a
  frame at a delimiter or EOF, rejecting suffix payloads.
- `upstream/jq/tests/jq.test:1290-1293` is the pinned CLI behavior probe.
- `upstream/jq/tests/jq.test:2281-2290` records jq's rejection of `NaN1`,
  `NaN10`, and related payload spellings.

Focused coverage is in `compat/cli-nonfinite-framing.jq.test`; direct CLI probes
also cover invalid `NaN1` and `Infinity0` payloads.
