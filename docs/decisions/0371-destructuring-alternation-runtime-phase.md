# Decision 0371: bounded runtime activation for array alternation

Status: accepted for the narrow valid-jq shape; general pattern capture remains deferred.

The evaluator now activates an `Alternation` program instruction when the producer
is identity and each branch is a one-slot array pattern containing one variable.
Branches are attempted against an owned copy of the original input; a failed branch
does not consume that copy, and a successful branch runs the body on a fresh clone.
This covers `. as [$a] ?// [$b] | .` without rewriting the source or AST.

The exact compatibility fixture is `compat/destructuring-alternation-runtime.jq.test`.
Its `[1]`, `[]`, and `[1,2]` cases match the pinned jq oracle. Non-array input raises
and `null` preserves jq's null indexing behavior; booleans, strings, objects, and
numbers raise the corresponding indexed-type runtime errors. Literal-value patterns,
object-pattern fallback, generator producers, variable capture visibility in the
body, and rollback across
multiple outputs remain unsupported and must not be inferred from this phase.

Ownership evidence is in `src/eval/evaluator.odin:1670-1705` (branch matching) and
`src/eval/evaluator.odin:8770-8845` (original-input retention, branch activation, and
runtime error path). The retained value is destroyed by the existing frame cleanup
at `src/eval/evaluator.odin:720-735`.
