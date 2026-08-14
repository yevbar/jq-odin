# Decision 0319: bounded `$__loc__` object shorthand lowering

The jq catalog case at `upstream/jq/tests/jq.test:2262-2264` uses
`{ a, $__loc__, c }`. jq emits an `__loc__` object containing the top-level
filter filename and line. The current Odin program/evaluator ABI has no
source-name payload or location opcode, so this slice keeps the contract
bounded in the driver: only the exact three-entry shorthand shape (ignoring
whitespace) is lowered to an equivalent static object constructor with
`{"file":"<top-level>","line":1}`.

Standalone `$__loc__`, colon-valued forms, and other object shapes remain on
the parser's existing rejection path. This avoids silently broadening source
location behavior or changing the shared program ABI; a future general
location implementation must introduce an owned source metadata contract and
cover input/debug/location semantics together.

Evidence: `upstream/jq/tests/jq.test:2262-2264`.
