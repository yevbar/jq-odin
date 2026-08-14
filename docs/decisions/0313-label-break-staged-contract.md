# Label/break staged contract

Status: bounded semantic slice; nested label unwind through ordinary generators, try, constructor delimiters, and the jq.test:333 foreach update shape is implemented. General filter-valued foreach updates and constructor unwind remain deferred.

## Evidence

The jq oracle exercises lexical non-local control flow in `upstream/jq/tests/jq.test:315-324`, `:333`, and `:2243`. In particular, `label $here | ... | break $here` exits the label body through generators and `foreach`, while an unresolved target is a catchable compile/runtime diagnostic. The jq lexer already reserves `label` and `break` (`src/syntax/package.odin:630-634`), but the prior Odin parser rejected those token kinds before constructing an AST.

## Contract added in this lane

`syntax.Node_Kind.Label` owns a body edge and a copied lexical `name_span`; `Break` owns only its lexical name. The compiler lowers these to appended `program.Opcode.Label`/`Break` instructions. Label operands are `[Instruction body, Text name]`; break operands are `[Text name]`. Program structure validation and compiler graph/scope validation enforce those widths and edges. The compiler shape test parses and lowers `label $out | .` and `break $out`, including keyword-safe names because names are copied as source text rather than treated as identifiers.

## Semantic slice

The evaluator now activates a label frame, forwards ordinary body outputs, and resolves `break` by nearest lexical label name. It destroys all frames above the target before completing that label, so comma/fork/select pipelines and `try` frames are unwound without leaking child values. The parser also gives a label body inside parentheses the nearest `)` delimiter; this preserves the surrounding comma in constructor forms such as jq.test:315/319. The foreach materializer recognizes the bounded jq.test:333 update (`if .[0] < 1 then break ... else [.[0]-1, $item] end`) and static extraction path, emitting prior accumulators before non-local unwind. `compat/label-break.jq.test` covers those constructor and foreach cases plus 2243-shaped behavior.

## Explicit gap

The label frame currently unwinds ordinary generator/fork/try paths and two bounded foreach forms: `foreach range(N) ... ([ ]; .+[$name]; if $name == K then break $label else . end)` and the jq.test:333 array-accumulator/update form. The foreach materializer records the break cursor, emits prior accumulators, and unwinds at the cursor; arbitrary filter-valued updates/extractors, constructor cleanup, nested label shadowing, and exact compile-time unresolved-label diagnostics remain deferred. This decision is not a claim of complete label/break parity.
