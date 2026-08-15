# Decision 0360: bounded dynamic-index assignment implementation

Status: implemented on the dynamic-index assignment feature branch; integration
review remains required.

The jq.test:2044 shape `(.[{}] = 0)?` now has a narrow first-class contract:
the parser recognizes a root `Index` whose key is an instruction and whose base
is identity, and lowers the scalar RHS to `Dynamic_Index_Assign`. The compiler
and Program packages carry the key and RHS instructions as explicit operands.
The evaluator captures key and RHS streams in resumable phases, applies a
copy-on-write root update, and preserves jq's typed index diagnostics and
optional/try suppression. Nested dynamic paths, arbitrary RHS generators, and
string-key mutation remain outside this slice.

Evidence:

- `src/syntax/parser.odin:3190-3226` performs the root-only lowering and keeps
  the parenthesized close token available for the outer `?` wrapper.
- `src/compiler/package.odin:1482-1483` emits the three explicit operands;
  `src/program/package.odin:611-714` validates the opcode shape and child count.
- `src/eval/evaluator.odin:8396-8411` starts key capture, while
  `src/eval/evaluator.odin:11701-11732` evaluates RHS and applies the update;
  `src/eval/evaluator.odin:3823-3827` handles stream exhaustion.
- `upstream/jq/tests/jq.test:2044-2045` is the compatibility target.

Pinned jq 1.8.1 probes show `(.[{}] = 0)?` emits no output for null, arrays,
objects, numbers, and strings. Without optional suppression, `try (.[{}] = 0)
catch .` preserves `Array/string slice indices must be integers`, `Cannot index
object with object`, and `Cannot index number with object`; the focused fixture
records these outputs.
