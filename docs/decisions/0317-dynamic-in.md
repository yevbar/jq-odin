# Decision 0317: resumable generator `IN`

The program already carried an `In` opcode and a literal-only evaluator path.
This change preserves the opcode while adding resumable continuations for
filter-valued `IN(generator)` and `IN(source; s)`. The one-child form runs
against a clone of the original input; each output is compared with
`values_equal`, and the continuation short-circuits to `true` or emits
`false` after exhaustion. The two-child form streams the second argument as
the outer generator and launches the first argument for each of its values.
This preserves jq's lazy intersection ordering: a later source value can
match before a later error in the outer generator, and a match destroys both
child frames immediately.

Uppercase `IN` is normalized by the parser because jq exposes that spelling
as the builtin. `inside` has distinct containment semantics and remains
explicit follow-up work rather than being silently approximated.
