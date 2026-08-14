# Decision 0317: resumable one-argument `IN`

The program already carried an `In` opcode and a literal-only evaluator path.
This change preserves the opcode while adding resumable continuations for
filter-valued `IN(generator)` and `IN(source; s)`. The one-child form runs
against a clone of the original input; each output is compared with
`values_equal`, and the continuation short-circuits to `true` or emits
`false` after exhaustion. The two-child form materializes source outputs in an
owned array, then evaluates the second child against the same cloned input
and compares each result with the materialized source values.

Uppercase `IN` is normalized by the parser because jq exposes that spelling as
the builtin. `inside` has distinct containment semantics and remains explicit
follow-up work rather than being silently approximated.
