# Static slice assignment with multi-output RHS

Status: implemented as a bounded evaluator extension from integration commit
`c990c3b4`.

The existing `Static_Slice_Set_Number` instruction already preserves numeric
slice bounds and the RHS source span as text. The evaluator now parses that
text as a comma-delimited stream of literal JSON arrays, materializes one
updated array per RHS output, and emits those arrays through a resumable frame
phase. Static slice reads remain on the existing `Slice` path.

Evidence:

- `src/syntax/parser.odin:2329-2348` lowers static numeric slice assignment
  while retaining the RHS node span.
- `src/compiler/package.odin:739-747,1261-1278` emits the unchanged three-text
  operand ABI, including the RHS source spelling.
- `src/eval/evaluator.odin:1178-1190` validates those operands; the new
  `static_slice_apply` helper and `.Static_Slice_Active` phase retain one owned
  result per RHS output and release the temporary arrays on every path.
- `upstream/jq/tests/jq.test:478-482` is the pinned oracle case.

Focused coverage is in `compat/static-slice-multi-output.jq.test` and checks
three RHS outputs, existing reads, null-source materialization, and catchable
scalar errors.

Known limit: the bounded opcode still accepts literal JSON-array RHS terms
only. Dynamic RHS filters and non-array literal RHS remain outside this
contract and must not be inferred as supported.
