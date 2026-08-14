# Dynamic object-index assignment boundary

Status: audited and deferred from integration `c183851a`.

The jq.test:2044 filter `(.[{}] = 0)?` cannot be implemented by the existing
bounded assignment ABI without introducing a new dynamic path-update contract.
The parser's assignment branches accept only numeric `Index` nodes for
`Static_Index_Set_Number` and lower nested static paths to `Setpath`; a dynamic
`Index` with an instruction-valued key is not accepted by either path. The
existing evaluator supports dynamic instruction-valued keys only for read
`Index` frames, not updates.

Evidence:

- `upstream/jq/tests/jq.test:2044-2045` is the target optional assignment.
- `src/syntax/parser.odin:2497-2523` only routes child `Field`/`Index` paths
  through `static_assignment_path`, whose index component requires a numeric
  `number_text`; `src/syntax/parser.odin:3020-3075` similarly lowers only
  numeric static index assignment.
- `src/compiler/package.odin:1324-1344` emits `Static_Index_Set_Number` with
  text operands only; no dynamic-key assignment opcode exists.
- `src/eval/evaluator.odin:3990-4029` evaluates instruction-valued keys for
  read indexing and immediately propagates `dynamic_index_result`; it has no
  corresponding update continuation. `src/eval/evaluator.odin:8347-8410`
  handles only numeric static index assignment.

Pinned jq 1.8.1 probes:

- `.[{}]` on `null` returns `null`.
- `.[{}] = 0` raises `Array/string slice indices must be integers` on `null`,
  `[]`, and `[1,2]`; it raises `Cannot index object with object` on `{}` and
  `{"a":1}`, and `Cannot index number with object` on `1`.
- `(.[{}] = 0)?` suppresses each of those errors and emits no output.

The missing contract includes dynamic key evaluation, type-specific update
semantics, optional/try suppression, and ownership-safe resumable path updates;
implementing it as a textual rewrite or numeric special case would misrepresent
jq behavior and broaden the assignment ABI unsafely.
