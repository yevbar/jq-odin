# Decision 0394: `Binding_Path_Assign` runtime remains deferred

Status: decision-only after an isolated runtime attempt on integration `3b1d1bf9`.

## Oracle probes

Pinned jq 1.8.1 behavior for `(.a as $x | .b) = "b"` is:

| input | result |
| --- | --- |
| `{"a":1,"b":2}` | `{"a":1,"b":"b"}` |
| `null` | `{"b":"b"}` |
| `[1,2]` | `Cannot index array with string "a"` |
| `1` | `Cannot index number with string "a"` |

Wrapping the assignment in `try (...) catch .` yields the same objects for object/null and catches the exact string errors for array/number.  An outer RHS `$x` (`(.a as $x | .b) = $x`) is a jq compile error (`$x is not defined`); the binding scope ends with the parenthesized path expression.

## Source boundary

The parser/compiler/program already preserve this shape as a two-child `Binding_Path_Assign` (`src/syntax/parser.odin:4141-4158`, `src/compiler/package.odin:1691-1695`, `src/program/package.odin:747-750`).  The evaluator still rejects the opcode at dispatch (`src/eval/evaluator.odin:8864-8865`).  Ordinary `Binding` frames evaluate the left generator, retain `binding_value`, then run the body against a clone of the original input (`src/eval/evaluator.odin:5106-5131`); a correct assignment continuation must retain that original root while converting the body into a path, preserving lexical scope and error cardinality.  Existing static-field update code can synthesize an object from null, but cannot be reused directly because it does not execute the binding producer first (`src/eval/evaluator.odin:9468-9496`).

## Disposition

Do not merge a direct-field shortcut or textual rewrite.  The smallest safe follow-up is an explicit continuation that (1) evaluates the binding producer for typed errors, (2) retains the original root and binding environment, (3) captures the body path stream, and (4) applies the RHS with copy-on-write and `try` propagation.  The attempted shortcut remained `internal misuse` across all four input classes, so no source changes are retained.
