# Label/break staged contract

Status: bounded semantic slice; nested label unwind through ordinary generators and try is implemented. Foreach/constructor unwind remains deferred.

## Evidence

The jq oracle exercises lexical non-local control flow in `upstream/jq/tests/jq.test:315-324`, `:333`, and `:2243`. In particular, `label $here | ... | break $here` exits the label body through generators and `foreach`, while an unresolved target is a catchable compile/runtime diagnostic. The jq lexer already reserves `label` and `break` (`src/syntax/package.odin:630-634`), but the prior Odin parser rejected those token kinds before constructing an AST.

## Contract added in this lane

`syntax.Node_Kind.Label` owns a body edge and a copied lexical `name_span`; `Break` owns only its lexical name. The compiler lowers these to appended `program.Opcode.Label`/`Break` instructions. Label operands are `[Instruction body, Text name]`; break operands are `[Text name]`. Program structure validation and compiler graph/scope validation enforce those widths and edges. The compiler shape test parses and lowers `label $out | .` and `break $out`, including keyword-safe names because names are copied as source text rather than treated as identifiers.

## Semantic slice

The evaluator now activates a label frame, forwards ordinary body outputs, and resolves `break` by nearest lexical label name. It destroys all frames above the target before completing that label, so comma/fork/select pipelines and `try` frames are unwound without leaking child values. `compat/label-break.jq.test` covers jq.test 315, 319, and 2243-shaped behavior.

## Explicit gap

The label frame currently unwinds ordinary generator/fork/try paths. A follow-up evaluator lane must exercise and repair constructor and foreach frame cleanup (jq.test 333), verify nested label shadowing, and move unresolved-label resolution to compile time so jq's exact non-catchable diagnostic is reproduced. This decision is not a claim of complete label/break parity.
