# 0027: Source comparison syntax

- Status: proposed
- Date: 2026-08-03
- Workstream: language

## Context and evidence

jq gives `==`, `!=`, `<`, `<=`, `>`, and `>=` distinct tokens. The lexer lists
the two-byte spellings before the single-character `<` and `>` rule
(`upstream/jq/src/lexer.l:48-49,77-81`). The grammar declares all six at one
non-associative precedence tier below arithmetic and above `and`, and provides
one `Expr op Expr` production for each
(`upstream/jq/src/parser.y:50-59,86-87,100-112,397-413`). Numeric comparison
fixtures exercise all six operators, and the shell suite includes each compact
spelling among constant expressions (`upstream/jq/tests/jq.test:1372-1384`;
`upstream/jq/tests/shtest:42-51`).

Direct probes used the official jq 1.8.1 Linux AMD64 binary, reporting
`jq-1.8.1` with SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`.
They accepted arithmetic on either side, unary negation, postfix optional,
comments after an operator, and explicitly grouped comparison operands. They
rejected `1 < 2 < 3` at the second `<` and `1 == 1 != 0` at `!=`.
Malformed `1 < = 2`, `1 <== 2`, `1 !== 2`, `1 <> 2`, `1 <= >= 2`, missing
operands, and a standalone `!` also failed to compile.

The generated parser's shared state/value/location stacks start at 200 entries
and cap growth at 10,000 (`upstream/jq/src/parser.c:1690-1704,2247-2264,
2320-2385`). Checksum-pinned probes found the comparison last-success/first-
exhaustion unary-minus boundaries at 9,995/9,996 on the left, 9,993/9,994 on
the right, and 9,992/9,993 for the right operand inside one group. With a
comparison and tighter arithmetic operator both pending on the right, the
boundary is 9,991/9,992.

## Decision

Extend the existing `Node_Form.Binary` payload and append six comparison
members to `Binary_Operator`, preserving the existing arithmetic member values.
A comparison node uses the same two borrowed Parser-arena operand indices,
exact borrowed operator span, full expression span, and source-lifetime rules
as an arithmetic Binary node. It owns no runtime value or source text.

The iterative precedence parser adds one comparison tier below arithmetic.
Arithmetic nodes reduce before a following comparison. A pending comparison
does not reduce or shift when the next token is another comparison at the same
tier; the second operator is reported as the stable unexpected-token span.
Closing an explicit parenthesized frame reduces its comparison first, so
grouped comparison operands remain valid.

Pending comparisons use the existing incomplete Binary arena-node link and
the existing two-live-entry generated-parser accounting. No recursive parse or
cleanup path and no new allocation owner are introduced. All partial nodes
remain Parser-owned after input or resource failure.

## Alternatives

- Separate node forms were rejected because comparison operands, spans, and
  ownership are identical to the established Binary payload.
- Treating comparisons as left- or right-associative was rejected because jq's
  `%nonassoc` declaration and direct probes reject unparenthesized chains.
- Recursive precedence descent was rejected because the established parser
  contract preserves jq's 10,000-entry boundary without relying on native
  call-stack depth.

## Consequences

This extends the public syntax operator enum and therefore affects the direct
`compiler` consumer and future program/evaluator lowering. The compiler's
existing form guard continues to reject every Binary node as `Invalid_AST`;
comparison compilation and evaluation remain deliberately unimplemented. No
package, import edge, runtime `Value`, allocator owner, or ownership shard is
added. `operator_span` remains a borrowed span governed by
`language-own-017`.

## Validation

Focused lexer/parser tests cover every operator, longest-match and exact spans,
whitespace/newline/comment boundaries, arithmetic/query/unary/postfix
precedence, non-associative rejection, explicit grouping, malformed and missing
operands, allocation-failure cleanup, and the observed 10,000-entry boundaries.
Run the established syntax and repository mode/thread/sanitizer matrix, then
`make validate` and `git diff --check`.

Required adversarial-review lanes: detached source-aware parser parity,
ownership/resource safety, and malformed/boundary test-gap review.
