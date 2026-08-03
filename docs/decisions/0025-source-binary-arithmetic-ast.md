# 0025: Source binary arithmetic AST contract

- Status: proposed
- Date: 2026-08-03
- Workstream: language

## Context and evidence

jq lexes `+`, `-`, `*`, `/`, and `%` as separate single-byte punctuation
tokens (`upstream/jq/src/lexer.l:81`). Its grammar declares binary `+` and `-`
left-associative, then declares binary `*`, `/`, and `%` left-associative at the
next tighter precedence tier (`upstream/jq/src/parser.y:100-112`). The matching
`Expr` productions lower each of those five operators separately
(`upstream/jq/src/parser.y:348-417`). Comma and pipe are `Query` productions at
looser tiers, while parentheses contain a complete `Query`
(`upstream/jq/src/parser.y:100-103,324-345,655-656`). General postfix optional
and recursive unary minus are `Term` productions, so each binds before binary
arithmetic (`upstream/jq/src/parser.y:545-656`). The accepted jq fixtures expose
tighter multiplicative precedence and left-associative additive and
multiplicative chains (`upstream/jq/tests/jq.test:641-651`).

Direct probes used the official jq 1.8.1 Linux AMD64 binary, reporting
`jq-1.8.1` with SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`.
They compiled `1+-2`, `1--2`, `1*-2`, `1/-2`, `1%-2`, `1+2?`, `(1+2)?`,
`1?+2`, `1+2,3`, `1,2+3`, `1+2|3`, and `1|2+3`. They rejected `1+`, `+1`,
`1++2`, `1+*2`, `1*/2`, `1 2`, `1+)`, `(1+2`, and `(1+)` as syntax or
lexical errors rather than successful filters.

The generated parser shares a 10,000-entry state/value/location stack and
takes its memory-exhausted path when it cannot grow further
(`upstream/jq/src/parser.c:1690-1704,2247-2264,2320-2385`). Checksum-pinned
boundary probes found that 9,995 unary minuses before the left operand of
`+ 2` compile and 9,996 exhaust the parser; on the right of an already shifted
`1 +`, 9,993 compile and 9,994 exhaust; inside one surrounding group the
right-operand boundary is 9,992/9,993. A comma awaiting its right Query retains
two more entries while a tighter binary right operand is parsed: `1,2+` plus
9,991 unary minuses and `3` compiles, while 9,992 exhausts. The neighboring
last-success/first-failure boundaries are 9,990/9,991 inside one group,
9,990/9,991 with a postfix on the binary right operand, 9,989/9,990 with a
suspended outer pipe and comma, and 9,988/9,989 with two commas suspended
across a group. These observations are generated-parser resource behavior,
not a grammar nesting limit.

## Decision

`syntax.Node_Form.Binary` represents all five source-level arithmetic forms;
its separate discriminator lets downstream exhaustive `Node_Kind` switches
continue compiling until arithmetic lowering is assigned. `kind` has no
semantic meaning when `form` is `Binary`. A completed Binary node has two
Parser-arena indices, `left` and `right`, a
`Binary_Operator` value (`Add`, `Subtract`, `Multiply`, `Divide`, or `Modulo`),
an exact half-open `operator_span` for the punctuation token, and a full `span`
from the left operand start through the right operand end. The operator span
must belong to the Parser's exact borrowed Source and must be contained in the
node span. Binary nodes own no text or child storage.

The parser uses an iterative two-tier operator stack encoded temporarily in
incomplete Binary arena nodes. Equal-precedence nodes reduce before shifting
the next operator, producing left associativity; multiplicative nodes remain
open above additive nodes, producing the tighter tier. Every completed node
clears its temporary link. Partial nodes remain Parser-owned after input or
resource failure and are released with the arena.

Parenthesized parsing now stores suspended scalar parser state in a private
fallible `Parse_Frame` buffer owned by `Parser`. This avoids native recursion
and avoids exposing parser-only links in completed public AST nodes. Frame
growth has the same explicit old/replacement transfer states and retryable
release rules as the node and scanner buffers. `destroy_parser` releases or
retires the frame buffer with the captured allocator and preserves remaining
owners after a genuine release failure.

The event-local stack budget counts two live generated-parser entries for each
pipe, comma, or binary operator awaiting its right operand. Completed commas
leave the live total before a same-tier comma is shifted. Resource exhaustion
remains `Parse_Outcome_Kind.Resource_Failure`; it is never converted to an
input diagnostic.

## Alternatives

- Five separate node kinds were rejected because their ownership and edge
  shapes are identical and a closed operator enum keeps exhaustive consumers
  explicit without duplicating the node contract.
- Erasing operator punctuation after selecting a kind was rejected because it
  loses the requested exact operator location.
- Recursive precedence descent was rejected because jq-compatible deep prefix
  and group cases must not depend on the Odin host call stack.
- Encoding suspended group state in otherwise semantic public Node fields was
  rejected because completed AST shape should not expose parser mechanics.

## Consequences

This changes the public `syntax.Node` contract without adding a package or
import edge. The direct current downstream consumer is `compiler`;
future `program` and `eval` work also consume the lowered meaning. The direct
compiler consumer checks `Node.form` before `Node.kind`, rejects every Binary
form as `Invalid_AST`, and rejects Kinded nodes that carry any binary-only
operator payload. Rejection is allocation-free and leaves Program output
inert. Arithmetic lowering must be sequenced as a separate program/compiler
task and must validate both operand indices, the operator enum, and both source
spans. The minimal direct-consumer guard does not add a package edge or
implement arithmetic lowering.

The caller continues to own source bytes. `operator_span` is invalid when the
Parser's source borrow ends; destroying a Binary AST performs no per-node or
per-operator release. `Parser.frames` is private parser state and never appears
in a successful AST view.

## Validation

Focused syntax tests cover every operator, exact expression/operator/operand
spans, both precedence tiers, left-associative chains, parentheses, unary-minus
chains, optional, comma, pipe, whitespace and token boundaries, malformed and
missing operands, distinct-source rejection, allocation failure at every
request, frame-growth transfer failure and cleanup retry, and checksum-pinned
9,995-scale parser-stack boundaries, including neighboring comma/binary,
group, pipe, postfix, and combined-Query transitions. Focused compiler tests
reject Binary and every inconsistent Kinded cross-form shape before allocation
and prove Program output remains inert. Run the complete repository matrix in
default, debug, speed, assertions-disabled, and ASan/LSan modes at thread
counts 1 and 4 with an 8 MiB stack, followed by `make validate`.

Required adversarial-review lanes: source-aware semantic parity, Odin
ownership/resource safety, and parser test-gap review.
