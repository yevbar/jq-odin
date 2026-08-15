# Decision 0340: bounded literal `getpath` assignment

## Scope

Support the exact scalar-RHS form `getpath(["a",0,"b"]) |= 5` by lowering
the parser's literal `getpath` node to the existing `Setpath` instruction.
The accepted path is an array containing only literal strings and numbers;
the RHS is one literal scalar.  This covers jq.test:1241 and preserves the
existing copy-on-write path evaluator.

Dynamic path filters, variable paths, generator RHS streams, and nested
filter-valued updates remain deferred.  They require a first-class resumable
path-update contract rather than parser aliases.

## Evidence

`src/syntax/parser.odin` already parses `getpath` with one argument, while
`src/eval/evaluator.odin` already owns literal path materialization and
`Setpath` copy-on-write updates.  The new lowering validates the literal path
shape and routes typed path failures through catchable runtime diagnostics.

Focused compatibility fixture `compat/getpath-static-update.jq.test` matches
pinned jq 1.8.1 for valid synthesis and number/object path errors.
