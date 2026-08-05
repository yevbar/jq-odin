# 0028: Source boolean and alternative syntax

- Status: proposed
- Date: 2026-08-03
- Workstream: language

## Context and evidence

jq gives `and`, `or`, and `//` distinct tokens, with the keyword rules and
two-byte punctuation rule preceding identifier and single-character fallback
rules (`upstream/jq/src/lexer.l:48-81,129-130`). The grammar declares `//`
right-associative, then `or` and `and` as successively tighter left-associative
tiers. All three remain looser than the non-associative comparison tier and
tighter than comma and pipe (`upstream/jq/src/parser.y:100-112`). Their three
`Expr op Expr` productions lower independently (`upstream/jq/src/parser.y:348-360`).
Upstream fixtures exercise boolean forms, alternative selection, their use
inside arrays and objects, and `and` combined with comparison and pipe forms
(`upstream/jq/tests/jq.test:1353-1364,1447-1447,1472-1472,2093-2093`).

Direct probes used the official jq 1.8.1 Linux AMD64 binary, reporting
`jq-1.8.1` with SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`.
Distinct-result probes confirmed `and` binds tighter than `or`, comparisons
bind tighter than both, and `//` binds more loosely than both boolean tiers but
more tightly than comma and pipe. AST-independent malformed probes rejected a
missing operand on either side of every operator and separated `/ /` tokens.

The generated parser shares capped state/value/location stacks and reaches its
memory-exhausted path when they cannot grow
(`upstream/jq/src/parser.c:1690-1704,2247-2264,2320-2385`). Checksum-pinned
probes found that a right-associative chain of 4,997 `//` operators parses
before later compilation rejects its size, while 4,998 exhausts the parser.
For one pending `and`, `or`, or `//`, 9,993 unary minuses on the right parse
and 9,994 exhaust the parser.

## Decision

Append `Defined_Or`, `Or`, and `And` to the existing `Binary_Operator` enum so
all established arithmetic and comparison values remain stable. Each uses the
existing `Node_Form.Binary` payload: two borrowed Parser-arena operand indices,
an exact borrowed operator span, and a full expression span. These nodes own no
source bytes, text, or runtime value.

Extend the iterative precedence parser with three lower tiers. Equal-precedence
`and` and `or` nodes reduce before shifting, producing left associativity;
equal-precedence `//` nodes remain pending, producing right associativity.
Comparison non-associativity, tighter arithmetic, and looser Query-level comma
and pipe behavior remain unchanged. Pending nodes continue to be the sole
operator stack and use the existing two-live-entry generated-parser accounting.

## Alternatives

- Separate node forms were rejected because operands, spans, and ownership are
  identical to the established Binary payload.
- Desugaring boolean and alternative operators during parsing was rejected
  because this slice is syntax-only and must preserve exact source operators.
- Recursive right-hand parsing for `//` was rejected because it would replace
  jq's explicit 10,000-entry boundary with the Odin call-stack limit.

## Consequences

This extends the public syntax operator enum and therefore affects the direct
`compiler` consumer and future lowering. The compiler's existing Binary-form
guard continues to reject the nodes as `Invalid_AST`; compiler and evaluator
semantics remain unimplemented. No package, import edge, allocator owner, or
ownership-shard row changes. `operator_span` remains governed by
`language-own-017`.

## Validation

Focused parser tests cover all three operators, exact spans, precedence,
associativity, grouping, comments/newlines, malformed forms, allocation failure
and retryable cleanup, and the exact generated-parser stack boundaries. Run the
syntax default/debug/speed/assertions-disabled/ASan+LSan and thread 1/4 matrix,
then `make validate` and `git diff --check`.

Required adversarial-review lanes: detached source-aware parser parity,
ownership/resource safety, and malformed/boundary test-gap review.
