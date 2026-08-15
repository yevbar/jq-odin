# Decision 0354: staged parameterized callable ABI

This phase adds the smallest owned representation for a one-parameter,
one-argument callable without changing the existing zero-argument call ABI.
The syntax package records an optional declaration parameter span and emits a
`Call` with a second operand for the argument root. The compiler preserves the
callee body as operand zero and lowers the argument filter as operand one.
`program.Callable_Entry` carries fixed-width immutable ordinal, arity, and body
metadata; the evaluator call-frame prototype carries the argument instruction
edge so a future activation can transfer ownership into a callee frame.

The parser rejects an extra positional argument (`id(1,2)`) because this phase
supports exactly one parameter, and rejects parenthesized calls to zero-argument
definitions (`def zero: 1; zero(2)`). Top-level zero-argument definitions and
their recursive/declaration-snapshot behavior remain unchanged.

This is an ABI and structural validation checkpoint, not full runtime binding:
the production evaluator still accepts only one-operand `Call` instructions.
Argument evaluation, parameter binding, multi-parameter arity diagnostics,
and filter-valued assignment remain a follow-up evaluator contract. No driver
or textual expansion is used to simulate those semantics.

Evidence: `src/syntax/parser_test.odin` covers `def id(x): x; id(1)` and rejects
`id(1,2)`; `src/compiler/compiler_test.odin` checks the two instruction edges;
`src/program/program_test.odin` checks fixed-width callable metadata; and
`src/eval/call_frame_prototype_test.odin` checks argument-edge ownership across
frame push/return. The existing jq compatibility probes for parameterized
definitions therefore remain intentionally deferred until evaluator activation
is implemented.
