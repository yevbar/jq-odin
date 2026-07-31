# 0004: Syntax token and scanner contract

- Status: accepted
- Date: 2026-07-30
- Workstream: integration, language

## Context and evidence

jq lexer locations are half-open byte offsets
(`upstream/jq/src/lexer.l:10-15`). Comments, whitespace, reserved words,
operators, punctuation, format names, bindings, identifiers, field shorthand,
and delimiter matching all have byte-oriented lexical behavior
(`upstream/jq/src/lexer.l:41-93,129-181`). jq assignment-family tokens are
language operators with precedence and stream/path semantics, not storage
assignment (`upstream/jq/src/parser.y:100-110`).

The pinned Odin language has no generator or coroutine primitive. Odin strings
are immutable, length-delimited views, and slices or strings do not carry an
owner. A scanner contract must therefore make source lifetime and resumable
state explicit.

Numeric and interpolated-string token details remain disputed in the evidence
shard. They must not be guessed while implementing the first lexer kernel.

## Decision

`syntax.Token` is a non-owning description of source bytes:

- `kind` identifies the jq token;
- `span` is a `diagnostic.Span` covering the complete token in half-open byte
  offsets and carrying the identity of the scanner's source;
- an optional `value_span` identifies a source subrange when jq strips a
  prefix, such as `$` from a binding or `@` from a format name;
- neither field owns or copies source bytes.

The scanner is initialized with one borrowed `diagnostic.Source` and creates
every token span through that source. When present, `value_span` has the same
source identity and is fully contained within `span`. The caller retains that
exact, unmodified Source value and its unchanged backing strings for the
lifetime of the scanner and every token, lookahead entry, AST span, or
diagnostic derived from the scan. Raw spelling is recovered only from that
source plus a structurally validated span. Tokens do not store `cstring`,
decoded JSON values, or pointers into growable arrays.

`syntax.Scanner` is an explicit state machine, not a coroutine. A
`next_token`-style operation advances once and returns exactly one of token,
end-of-input, lexical error, or resource failure. Lexical error means the input
bytes violate the jq lexical grammar; resource failure means scanner-owned
state could not allocate or grow and must never be presented as an input
diagnostic.

After resource failure the scanner enters a terminal failed state. It owns no
partial allocation from the failed operation, remains safe to destroy, and
subsequent advancement returns the same failure without consuming input or
allocating. The scanner owns any delimiter/state stack, records its allocator,
and has explicit initialization and destruction. The recorded allocator and
all backing state reachable through it (including arena storage, allocator
userdata, and callback state) must remain valid through scanner destruction.
An implementation may instead document a terminal retirement operation that
first releases or retires all scanner-owned storage; destruction and every
other operation permitted after that point must then be allocator-free.
Arena-backed scanners must be destroyed or retired by that operation before
arena teardown. A terminal failed scanner is not thereby retired when its
later destruction can still release scanner-owned storage. Copying a live
scanner with Odin `=` is forbidden.

The first lexer milestone covers only accepted evidence for whitespace,
comments, punctuation, delimiters, reserved/multi-character operators,
identifiers, bindings, format names, and field shorthand. It must:

- preserve jq operator kinds exactly, including `=`, `|=`, compounds, `//`,
  and `?//`;
- maintain delimiter-specific state and reject a mismatched closer at that
  closer's byte span;
- implement backslash-newline continuation inside comments;
- report unmatched bytes as lexical errors without converting them to Unicode
  code-point offsets;
- keep jq assignment operators distinct from Odin's `=`, `:=`, and `::`.

Numbers and double-quoted/interpolated strings may receive placeholder token
kinds but cannot be claimed compatible until their disputed evidence is
resolved. Source-level literals remain raw syntax; the scanner and syntax
package do not import runtime `value`.

## Alternatives

- **Return a prebuilt token array.** Rejected as the only API because it hides
  allocation/failure points and prevents incremental parser integration.
- **Use an Odin iterator closure or thread as a generator.** Rejected because
  it does not provide language-level coroutine semantics and complicates
  ownership.
- **Copy token text into each token.** Rejected because spans already identify
  immutable input and per-token allocation would be unnecessary.
- **Decode JSON literals in the lexer.** Rejected because syntax must not
  import runtime `value`, and string/number edge behavior is not yet fully
  accepted.
- **Use code-point columns.** Rejected because jq's lexer and diagnostics are
  byte-oriented.

## Consequences

`syntax` imports `diagnostic` and no `value` package. A later parser owns token
lookahead and AST allocation; it may retain spans only while the source owner
remains live. The scanner cannot return borrowed token text without also
naming that lifetime in its API.

Adding literal decoding, parser recovery, or AST nodes requires a follow-up
decision if it changes public token payloads or source ownership.

## Validation

- Checked-in lexer tests for every accepted operator and punctuation token.
- Exact half-open spans for ASCII and multibyte UTF-8 input.
- Comment EOF and backslash-newline continuation cases.
- Balanced nested delimiters and every mismatched closing delimiter.
- Identifier, namespace, binding, format, and field-shorthand payload spans.
- Every token rejects a different source identity; every `value_span` is
  same-source and contained within its full token span.
- Allocation-failure and destroy tests for scanner-owned state.
- A retired/detector allocator test proves that allocator backing state stays
  valid through scanner destruction (or the documented terminal retirement
  operation) and that destruction and every other operation permitted after
  retirement make no allocator calls.
- Tests prove resource failure is distinct from lexical error, is atomic, and
  leaves a terminal scanner safe to query again and destroy.
- jq fixture comparison for the assigned lexical shard, then `make validate`.
- Independent source-aware semantic-parity and Odin ownership/safety reviews.
