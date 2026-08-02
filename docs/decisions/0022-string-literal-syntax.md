# 0022: Parser-owned plain string literal syntax

- Status: proposed
- Date: 2026-08-02
- Workstream: language

## Context and evidence

A quote enters jq's exclusive string lexer state. That state emits separate
start, text, interpolation-start, and end tokens; escaped fragments are grouped
and passed through `jv_parse_sized`, while raw fragments go directly through
`jv_string_sized` (`upstream/jq/src/lexer.l:99-125`). The grammar combines the
start, zero or more text/interpolation segments, and end into `String`, and
accepts that form wherever it accepts a `Term`
(`upstream/jq/src/parser.y:505-530,643-656`). Invalid decoded text is diagnosed
at its complete lexer token span before partial compiled output is discarded
(`upstream/jq/src/parser.y:145-160,956-970`).

The JSON decoder accepts quote, reverse-solidus, slash, backspace, form feed,
tab, newline, carriage return, and four-hex-digit Unicode escapes. It combines
a high and low UTF-16 surrogate into one scalar and emits UTF-8; malformed
escapes, missing/invalid low surrogates, and unescaped U+0000 through U+001F
have stable messages (`upstream/jq/src/jv_parse.c:446-503`). jq's UTF-8 helper
rejects invalid leading/continuation bytes, overlong forms, surrogate encodings,
and scalars above U+10FFFF, and its encoder emits one through four bytes
(`upstream/jq/src/jv_unicode.c:29-82,93-120`). The direct raw-text caller does
not reject those errors: `jv_string_sized` instead replaces badly encoded
points with U+FFFD (`upstream/jq/src/jv.c:1112-1143,1278-1282`).

Fixtures cover ordinary escaped Unicode text, invalid escape wording and the
complete escape-token caret, interpolation, and length-delimited embedded NUL
behavior (`upstream/jq/tests/jq.test:52-70,1408-1419,1919-1929`). Compile-fail
fixtures preserve exact source bytes and caret spans
(`upstream/jq/tests/jq.test:547-569,1949-1953,2032-2042`).

The official jq 1.8.1 Linux binary (SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`)
and the coordinator's audited byte fixtures resolve counterintuitive filter-
source behavior in favor of the observable oracle: raw U+0000 through U+001F
bytes are accepted as string text, malformed raw UTF-8 is replaced one
`jvp_utf8_next` decoding unit at a time with U+FFFD, and isolated low escapes
`\udc00` through `\udfff` compile as U+FFFD. For example, the source bytes
`22 ff c0 af e2 78 80 22` compile to
`22 ef bf bd ef bf bd ef bf bd ef bf bd 78 ef bf bd 22 0a`, while both
`"\udc00"` and `"\udfff"` produce UTF-8 `ef bf bd`. These results follow the
raw lexer caller and replacement loop above, including its exact invalid-unit
consumption. In contrast, `"\q"`, `"\u"`, `"\u12"`, `"\u12x4"`,
`"\ud800"`, `"\ud800\u0041"`, and `"\udc00\ud800"` exit 3 with their
invalid-escape, Unicode-escape, or surrogate-pair compile diagnostics. These
probes were run with `-cn`, using `-f /dev/stdin` where raw bytes could not be
carried in an argument. jq filter source is therefore not constrained by the
stricter JSON-text rules used when parsing JSON input.

Exact 8 MiB-stack probes against that same checksum-pinned binary also show
that String is not stack-equivalent to a one-token literal until reduction.
Empty, plain, escaped, Unicode, and malformed-raw-UTF-8 completed strings
succeed inside 9,993 groups and reach `memory exhausted` inside 9,994;
ordinary one-token leaves retain their 9,994-success/9,995-exhaustion boundary.
At 9,994 groups, an invalid escape such as `"\q"` still reports `Invalid
escape`, because the lexer rejects its first text lookahead before the extra
String grammar state is entered. Valid or unterminated progress instead reaches
the stack-exhaustion path. These boundaries follow the separate `StringStart`,
empty/iterative `QQString`, and `String` productions and the generated parser's
shared 10,000-entry cap (`upstream/jq/src/parser.y:505-530`,
`upstream/jq/src/parser.c:1690-1704,2247-2264,2320-2385`).

## Decision

Add `Node_Kind.String`. A completed node spans the opening quote through the
closing quote under the existing half-open byte convention and contains a
`string_text` Odin string plus `has_string_text`. The payload is decoded,
length-delimited bytes; it is never a `cstring` and may contain byte zero.
Interpolation and format strings remain unsupported and do not produce a
String node.

The parser consumes scanner string tokens iteratively, validates the complete
plain contents, computes the exact decoded length without allocation, allocates
independent backing with its captured allocator, and decodes in a second
iterative pass. It accepts all JSON escapes, BMP scalar escapes, valid UTF-16
pairs, raw U+0000 through U+001F bytes, and well-formed literal UTF-8. Malformed
raw UTF-8 and isolated low-surrogate escapes produce U+FFFD using jq's exact
invalid-unit boundaries. Invalid escape letters, malformed or truncated
`\u`, and invalid high-surrogate pairing remain rejected. No step recurses in
proportion to input length. Existing parser stack accounting treats String as
an ordinary completed Term leaf after charging the one-entry high-water
increment needed to enter its grammar state. That charge is event-local: a
lexical error fetched immediately after `String_Start` retains its diagnostic
instead of being replaced by parser-stack exhaustion.

Decoded sizing uses checked `u64` arithmetic and rejects an unrepresentable
source length or decoded-byte addition before narrowing to Odin `int`. This
includes the three-byte U+FFFD expansion for each malformed raw UTF-8 decoding
unit. The checked helper rejects multiplication/addition beyond `max(int)`
without modifying its accumulator; the only narrowing helper checks that same
bound. A size overflow becomes a deterministic resource failure before decoded
allocation or slicing, including in assertions-disabled builds.

Empty strings allocate one private backing byte while exposing a zero-length
string view, so their decoded view is independently backed without introducing
NUL-termination semantics. Nonempty allocations are exact decoded length.

`Parse_Error.message` is an optional borrowed static message. String failures
use the decoder messages established above and exact byte spans: scanner escape
and surrogate-pair failures retain their complete candidate span, while a
genuinely unterminated string reports its one-byte opening quote delimiter
rather than a synthesized zero-width EOF span. Thus valid raw text and complete
valid escapes followed by EOF use the opener, but a lone reverse-solidus,
truncated or malformed Unicode escape, invalid escape letter, or invalid high-
surrogate pairing retains its existing offending scanner span and diagnostic.
This resolves the opening-delimiter fallback disputed in `language-057` for
strings without adding parser state: the string parser already holds the
opening token span. The package does not render jq's outer `while parsing`
wrapper, so tests separately preserve oracle output for wording that differs.

Each decoded allocation is owned by the address-stable Parser and recorded in
a private `string_allocations` registry. Public mutable Node headers are payload
views, never cleanup authority. The caller may inspect decoded bytes after
releasing or changing source backing but must not resolve borrowed spans or call
`parser_source` after ending the source borrow. Decoded views and the borrowed
node-arena view are invalid once parser destruction begins.

Short or nil allocator results are resource failures. If retirement of a
malformed allocation fails, `pending_string_text` retains the sole handle for
destruction retry. Registry growth, node growth, and cleanup preserve the
existing transfer-pending and genuine-Free-error rules. Shallow Parser copies
remain forbidden and are rejected by runtime identity before any owned string
state is inspected. Empty, partial, invalid, interpolation, and resource-failed
strings never commit a String node.

The program-workstream owner delegated only the three exhaustive
`syntax.Node_Kind` switches in `src/compiler/package.odin`. They recognize a
completed String payload shape, classify it as unlowered, and return
deterministic `Invalid_AST` before allocation. The final lowering switch also
enumerates String defensively, but pre-allocation rejection makes it
unreachable for a valid String arena. No opcode, lowering, import edge, or
string execution behavior is added. Focused compiler tests pin valid nonempty
and empty parsed String nodes as allocation-free rejections and reject foreign
payload fields.

## Alternatives

- Borrowing raw contents was rejected because decoded bytes must survive source
  mutation and destruction.
- Storing runtime `Value` was rejected by the syntax package graph.
- One growable decode buffer was rejected because exact allocation and two
  iterative passes provide fewer ownership states.
- Using a public Node string header as cleanup authority was rejected because
  `parser_nodes` exposes mutable nodes.
- Accepting interpolation into the same node was rejected because segment AST,
  formatting, and lowering are separately owned work.

## Consequences

This changes the public syntax AST and parse-error contracts. Current direct
production consumers are syntax and compiler. Compiler behavior remains its
existing deterministic rejection; program, value, evaluator, driver, CLI, and
object-key grammar are unchanged. No package or import edge is added.

Callers retain source backing only for span use, not for decoded string bytes.
They retain the allocator and allocator backing through successful parser
destruction. A live Parser remains non-copyable and address-stable.

The compiler edits are a narrow cross-workstream sequencing exception. The
compiler owner must replace this deterministic rejection only in a later
Program-owned string-lowering slice backed by a separate accepted decision.

## Validation

Focused tests cover every escape, BMP and supplementary scalars, isolated low
surrogates, literal and malformed UTF-8, raw U+0000 through U+001F, empty and
embedded-NUL strings, exact spans, postfix/query composition, every remaining
rejection family and offset/message, interpolation, opening-delimiter EOF spans
for ASCII, UTF-8, multiline/raw-control, and complete-escape bodies, and the
distinct grouped spans for lone-backslash, malformed, and truncated escapes,
source independence
including replacement bytes after malformed-source release, private-registry
corruption resistance, nil/short/failing allocation, failed retirement and
cleanup retry, shallow-copy rejection, and a 100,000-segment iterative decode.
Focused compiler tests cover payload shape and allocation-free `Invalid_AST`.
The complete syntax matrix runs in default, debug, speed, assertions-disabled,
and AddressSanitizer modes with one and four threads and an 8 MiB stack where
supported. Exact stack regressions cover empty, plain, escaped, Unicode,
malformed-raw-UTF-8, invalid-escape, and unterminated strings at the oracle
boundaries without recursion. Pure sizing tests cover source length `max(int)`
and `max(int)+1`, exact decoded maximum and one-byte overflow, repeated
malformed-unit multiplication by three, accumulator preservation on rejection,
and checked narrowing without constructing unrepresentably large strings.
Validation concludes with `make validate`.

Required adversarial lanes: fresh source-aware Unicode semantic parity, Odin
ownership/resource safety, and parser diagnostic/test-gap review.
