# Decision 0317: resumable one-argument `IN`

The program already carried an `In` opcode and a literal-only evaluator path.
This change preserves that ABI while adding an evaluator continuation for
one-argument filter-valued `IN(generator)`. The child runs against a clone of
the original input; each output is compared with `values_equal`, and the
continuation short-circuits to `true` or emits `false` after exhaustion.

Uppercase `IN` is normalized by the parser because jq exposes that spelling as
the builtin. Two-argument `IN(source; s)` needs a two-child AST/operand
contract, and `inside` has distinct containment semantics; both remain
explicit follow-up work rather than being silently approximated.
