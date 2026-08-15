# Decision 0355: one-argument callable activation

The evaluator now activates a two-edge `Call` in a bounded one-argument form.
Operand zero is the immutable callee body and operand one is an argument filter.
The argument runs first; each emitted value is transferred into a real callee
frame, and the argument frame resumes after that body stream exhausts. Existing
one-edge zero-argument calls retain their direct body activation and recursive
frame behavior.

The driver routes only the exact identity fixture shape
`def id(x): x; id(...)` through the syntax/compiler/evaluator path. A comma in
the parentheses remains jq's generator operator (`id(1,2)`), while
semicolon-separated formal arguments (`id(1;2)`) are rejected. Other
parameterized definitions continue through the mature module bridge until
their lexical binding, multi-parameter arity, and generator semantics receive
their own contracts. This keeps the new runtime proof independent of textual
substitution while avoiding an unsafe broad driver cutover.

Evidence: `src/eval/evaluator_test.odin` executes a two-edge call and verifies
the argument value reaches the identity body; `src/driver/driver_test.odin`
checks the CLI-facing route, generator cardinality, and semicolon rejection. The call-frame phase remains
bounded and owns each argument value exactly once across body activation and
argument-generator exhaustion.
