# Dynamic trimstr operands

Status: implemented as a bounded evaluator vertical slice from integration
`ad31674f`.

`ltrimstr`, `rtrimstr`, and `trimstr` retain their existing one-instruction
operand ABI. Literal string children continue through the existing direct path,
including the established scalar-literal diagnostics. Nonliteral separator
filters and variables now enter resumable `Trimstr_Start_Child` /
`Trimstr_Child_Active` phases. The child receives a clone of the trimstr input;
each string result is consumed exactly once, owned separator values are
released, and the transformed output is propagated. Empty children emit no
outputs, multi-output children emit one result per separator, and child errors
remain catchable by the surrounding `try`.

The dynamic path raises the established catchable `startswith()`/
`endswith()` type diagnostic for non-string separators. If a separator stream
already yielded valid strings, those outputs remain observable before the
later error, matching jq's generator sequencing. Scalar literal diagnostics
remain unchanged.

Evidence is in `compat/dynamic-trimstr.jq.test`, targeting jq.test cases
2474/2481 and direct generator cardinality. Ownership boundaries remain in
`src/eval/evaluator.odin`; parser/compiler/program graph contracts remain
unchanged because the argument was already an instruction operand.

The dynamic child path also preserves the typed `startswith()`/`endswith()`
diagnostic when the original trimstr input is non-string, rather than exposing
an empty catch value. The four-pair regression cases in the focused fixture
cover both input and separator type failures.
