# Decision 0282: Evaluate generator-valued `contains` operands as child streams

## Status

Accepted for the bounded dynamic-contains slice.

## Decision

`contains(filter)` retains the original input in its parent frame, evaluates
the operand filter against a cloned input, and emits one containment result for
each operand output. The parent uses a dedicated `Contains_Child_Active` phase;
child exhaustion completes the frame, while each child output is consumed by
the existing containment kernel before being propagated to the surrounding
generator. Literal string/array/object operands keep the existing zero-child
path. Complete containment diagnostics are preserved both uncaught and as
`try`/`catch` values.

## Evidence

- `src/syntax/parser.odin` admits nonliteral `contains` operands through the
  stream-selector validation path.
- `src/eval/evaluator.odin` captures, validates, resumes, exhausts, and
  propagates `Contains_Child_Active` frames.
- jq oracle fixtures `upstream/jq/tests/jq.test:1615` and `:1619` pass 2/2.
- Direct and caught type-mismatch probes match jq, including child errors from
  string, null, number, and object inputs.
