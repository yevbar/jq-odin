# Dynamic slice-bound contract

Status: implemented as a bounded evaluator vertical slice from integration
commit `c164437f`.

The parser/compiler now preserve each Slice bound as either a `Text` operand
(the existing static numeric ABI) or an `Instruction` operand (a filter). The
program graph treats instruction-valued bounds as child edges without changing
the serialized static opcode or operand positions. The evaluator retains the
slice source separately from the original frame input, evaluates start and end
bound streams in resumable phases, and materializes one result per Cartesian
bound pair. Bound filters therefore observe the input before the slice child,
matching jq for `map([1,2][0:.])` (jq test 1707).

Numeric bounds use floor for starts and ceil for ends, normalize negatives
relative to the source length, and clamp to `[0,length]`; omitted bounds use
zero/length. Empty and multi-output filters preserve stream cardinality, and
bound errors remain catchable runtime errors. Owned source and bound values are
destroyed on normal, empty, error, and terminal paths through the existing
frame cleanup contract.

Evidence:

- `src/syntax/parser.odin` retains dynamic bounds as AST instruction nodes.
- `src/compiler/package.odin` emits `Instruction` bound operands while static
  number nodes remain `Text` operands.
- `src/program/package.odin` validates and traverses dynamic bound edges.
- `src/eval/evaluator.odin` implements the saved-source and resumable-bound
  phases; `compat/dynamic-slice.jq.test` covers identity, two dynamic bounds,
  multi-output, and fractional normalization against the jq oracle.

Known limit: dynamic string bounds and nonnumeric bound values follow the
existing evaluator's generic numeric runtime diagnostic wording; successful
array/string numeric semantics are covered by the focused probes.
