# Decision 0354: staged parameterized callable ABI

This phase adds the smallest owned representation for a one-parameter,
one-argument callable without changing the existing zero-argument call ABI.
The syntax package records an optional declaration parameter span and emits a
`Call` with a second operand for the argument root. The compiler preserves the
callee body as operand zero and lowers the argument filter as operand one.
`program.Callable_Entry` carries fixed-width immutable ordinal, arity, and body
metadata; the evaluator call-frame prototype carries the argument instruction
edge so a future activation can transfer ownership into a callee frame.

The parser treats comma as jq's generator operator inside the single
filter-valued argument (`id(1,2)` emits two values), rejects semicolon-separated
extra formal arguments (`id(1;2)`), and rejects parenthesized calls to
zero-argument definitions (`def zero: 1; zero(2)`). Top-level zero-argument
definitions and their recursive/declaration-snapshot behavior remain unchanged.

This decision records the structural ABI consumed by the evaluator activation
in 0355. The production evaluator now accepts the two-operand `Call` shape for
the bounded one-argument identity slice; lexical parameter binding,
multi-parameter arity diagnostics, and filter-valued assignment remain
follow-up contracts. No driver or textual expansion is used to simulate the
activated semantics.

Evidence: `src/syntax/parser_test.odin` covers `def id(x): x; id(1)` and rejects
semicolon-separated `id(1;2)`; `src/compiler/compiler_test.odin` checks the two instruction edges;
`src/program/program_test.odin` checks fixed-width callable metadata; and
`src/eval/call_frame_prototype_test.odin` checks argument-edge ownership across
frame push/return. The bounded identity activation is covered by
`compat/parameterized-call-activation.jq.test`; general parameterized
definitions remain intentionally deferred.
