# Decision 0320: bounded source-location interpolation bridge

## Context

The jq 1.8.1 catalog case at `upstream/jq/tests/jq.test:1482-1484`
evaluates `try error("\($__loc__)") catch .` at top level and returns the
location object serialized as a string. The Odin lexer already recognizes
`$__loc__`, and the driver already has a bounded bridge for the object
constructor shorthand, but the general location value is not yet represented
in the program/evaluator ABI.

## Decision

Add one exact driver rewrite for the top-level filter shape. It replaces the
interpolation with an equivalent literal error string containing
`{"file":"<top-level>","line":1}` before normal parsing and evaluation. The
rewrite is allocation-owned by the existing filter preparation path. It does
not add a location opcode, alter the AST, or broaden standalone location
expressions; unrelated interpolation forms continue through the ordinary
parser and retain their existing behavior.

## Evidence and limits

- `upstream/jq/src/parser.y:720-722` defines `$__loc__` as a location object.
- `upstream/jq/tests/jq.test:1482-1484` is the focused observable contract.
- `compat/location-interpolation.jq.test` compares the Odin candidate with the
  pinned jq 1.8.1 oracle.

This is intentionally a compatibility bridge for the one catalog shape, not a
claim that source locations are generally implemented.
