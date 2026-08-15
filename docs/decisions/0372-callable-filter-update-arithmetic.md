# Decision 0372: literal-field callable arithmetic update

Status: accepted bounded phase.

The callable identity-update ABI now admits the structurally validated body
`x |= .+N` when `N` is a numeric literal, while retaining the existing literal
field argument gate (`inc(.a)`). The parser records the numeric text on the
`Parameter_Identity_Update` marker; the compiler stores it as one owned `Text`
operand. The operand is not an instruction child: program validation accepts
zero or one operand and `instruction_child_count` remains zero. At call
activation the evaluator parses the borrowed program text into a number and
applies the existing binary-add implementation to the selected field in the
retained caller root, preserving ownership and jq's typed arithmetic error.

The generator argument `inc(.[].a)` remains unsupported and is intentionally
not routed through this specialization. A resumable path-stream continuation
is required before generator cardinality, empty-stream, or dynamic path cases
can be admitted.

Evidence: `compat/callable-path-identity-update.jq.test`; jq 1.8.1 oracle
matches the literal-field success and string-plus-number diagnostic.
