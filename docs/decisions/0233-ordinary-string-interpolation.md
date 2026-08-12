# Decision 0233: lower ordinary string interpolation through `tostring`

- Status: proposed
- Date: 2026-08-12
- Workstream: language, with focused compiler/evaluator integration

## Context and evidence

jq retains the leading string format across a quoted string, appends literal
`QQSTRING_TEXT` as constants, and lowers each interpolation query through
`gen_format` before string addition (`upstream/jq/src/parser.y:505-530`). An
ordinary quote supplies the literal format name `text`, and `gen_format`
compiles the query followed by `format(text)`
(`upstream/jq/src/parser.y:249-251,505-511`). The accepted lexer evidence also
establishes distinct interpolation boundaries and LIFO delimiter handling
(`evidence/claims/language.tsv`, language-008 and language-068).

The preceding bounded `@html` slice already demonstrates that this shape can
reuse `String`, `Pipe`, a formatter node, and binary `Add` without a new AST or
program operation (`docs/decisions/0232-html-format-interpolation.md`).

## Decision

Ordinary literal strings in expression position accept `\(query)` segments.
For the bounded JSON-value surface implemented here, the parser lowers every
embedded query to the behavior-equivalent `query | tostring`, keeps decoded
literal runs as existing owned `String` nodes, and joins adjacent segments with
existing binary `Add` nodes. Non-interpolated strings remain on their established
parser path; contiguous lexer text tokens within an interpolated literal run
are decoded into one literal node.

The shared interpolation helper is parameterized only by a fixed parser-
selected formatter. It is used for ordinary strings (`Tostring`) and the
existing bounded `@html` form (`Html`); it does not parse a dynamic formatter.

## Alternatives

A new interpolation AST kind and program opcode were rejected because existing
pipe, formatter, and addition semantics already preserve generator cardinality
and coercion. Reusing the broader `Text` evaluator opcode directly was rejected
because `Tostring` has the same observable coercion for the supported JSON
values and an explicit clone contract for string input. Rewriting interpolation
as parser source text was rejected because it would lose precise borrowed spans
and duplicate parsing.

## Consequences

Only syntax implementation and focused syntax/compiler/driver tests change.
There is no new package, import edge, public type, opcode, evaluator branch, or
value ownership rule. Decoded fragment storage remains owned by the parser's
existing allocation registry; compiler programs and evaluator results retain
their existing owners.

Quoted object-key and quoted-field interpolation remain rejected by their
existing non-interpolated parser path. Dynamic format operators, additional
formatted-string directives, assignment, and bespoke interpolation diagnostics
remain outside this slice.

## Validation

Focused syntax tests inspect lowering and allocation ownership, the compiler
test pins the reused opcode shape, driver tests exercise scalar coercion and
multi-result evaluation, the compatibility shard records jq-facing cases, and
CLI subprocess coverage checks the literal examples. Recommended adversarial
lanes are source-aware semantic parity and parser test-gap review.
