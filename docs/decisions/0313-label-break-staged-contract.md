# Label/break staged contract

Status: staged parser/program contract; evaluator unwind remains unimplemented.

## Evidence

The jq oracle exercises lexical non-local control flow in `upstream/jq/tests/jq.test:315-324`, `:333`, and `:2243`. In particular, `label $here | ... | break $here` exits the label body through generators and `foreach`, while an unresolved target is a catchable compile/runtime diagnostic. The jq lexer already reserves `label` and `break` (`src/syntax/package.odin:630-634`), but the prior Odin parser rejected those token kinds before constructing an AST.

## Contract added in this lane

`syntax.Node_Kind.Label` owns a body edge and a copied lexical `name_span`; `Break` owns only its lexical name. The compiler lowers these to appended `program.Opcode.Label`/`Break` instructions. Label operands are `[Instruction body, Text name]`; break operands are `[Text name]`. Program structure validation and compiler graph/scope validation enforce those widths and edges. The compiler shape test parses and lowers `label $out | .` and `break $out`, including keyword-safe names because names are copied as source text rather than treated as identifiers.

## Explicit gap

The evaluator currently returns `Unsupported_Opcode` for both opcodes. No compatibility case is counted as passing by this decision. A follow-up evaluator lane must add an active-label stack and non-local unwind that crosses fork, constructor, foreach, and try frames, and must preserve jq's unresolved-label diagnostic. This staged contract is intentionally not a claim of jq label/break parity.
