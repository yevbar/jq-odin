# 0002: Borrowed sources and byte-offset spans

- Status: proposed
- Date: 2026-07-30
- Workstream: language (diagnostic foundation delegated by integration)

## Context and evidence

jq lexer locations are half-open byte offsets (`upstream/jq/src/lexer.l:10-15`),
and grammar locations combine those offsets without converting them to
characters (`upstream/jq/src/parser.y:16-26`). Located diagnostics compute a
one-based line and byte-column from the start, echo the containing line, clamp
the underline to that line, and draw carets (`upstream/jq/src/locfile.c:79-90`).
Accepted fixtures expose the source name, indentation, and exact caret count
(`upstream/jq/tests/jq.test:547-569`,
`upstream/jq/tests/jq.test:1949-1953`).

The evidence row for `UNKNOWN_LOCATION` and the row asking which source range a
parser should attach to an unterminated construct are disputed. Neither
parser-level behavior is selected here.

## Decision

`diagnostic.Source` is a borrowed view containing length-delimited immutable
Odin strings for source name and source bytes. The caller keeps both backing
stores alive and unchanged while the view or a line borrowed from it is used.
`borrow_source` assigns each new view a process-unique, nonzero identity without
allocating. A returned `Source` may be copied unchanged, preserving its
identity, but callers must not rewrite any of its fields. Calling
`borrow_source` again creates a distinct view even when the name and content
strings compare equal or share the same backing storage.

`diagnostic.Span` stores a half-open byte range `[start, end)`. `make_span`
checks `0 <= start <= end <= len(source bytes)` and records the source-view
identity. Odin's `@(private)` attribute applies to top-level entities, not
individual struct fields, so the public value cannot be made fully opaque.
Validation is structural, not proof of provenance or a particular construction
path: a caller that has a span with a valid source identity can copy it and
replace its offsets with any other in-range pair. Every public operation that
exposes or consumes offsets takes the matching `Source`, checks the exact
generated identity, checks that its current string views match its recorded
pointer/length metadata, and validates the range. This rejects stale views,
separately borrowed sources, mismatched identities, and structurally
inconsistent metadata.

Because every `Source` field is public, a caller can copy a valid `Source`,
consistently replace its string views and matching pointer/length metadata, and
retain its identity. Structural validation cannot distinguish that value from
an unchanged copy. Such field rewriting is outside the valid API contract and
cannot be rejected as provenance forgery; callers must preserve the original
fields and keep the original backing strings valid and unchanged for the full
borrow lifetime.

The generated identity is not a hash of source bytes and provides no
cryptographic or construction-path provenance. Exhaustion stops rather than
reusing an identity. `Span` stores only the identity value, not source strings
or pointers, so it neither owns source storage nor extends the borrowed source
lifetime.

Location conversion uses the span start and returns a one-based line and
one-based byte-column plus a borrowed slice of the containing line. Rendering
known locations takes an explicit allocator and returns independently owned
storage that the caller frees with that allocator. It does not use or return
storage from `context.temp_allocator`. Temporary rendering storage is destroyed
on every path, every fallible append is checked, and successful output is
copied into an exact-length allocation before return.

The diagnostic layer accepts a zero-width span at end of source. Without a
trailing newline, `locate` returns the final source line and its column one past
the final byte; `render_error` echoes that line and draws one caret at that
column. With a trailing newline, `locate` returns the following empty line at
column one; `render_error` echoes the empty line and draws one caret at column
one. This policy only defines how an already-selected EOF span is located and
rendered. It does not decide whether a parser uses that span, or which span a
parser attaches to an unterminated construct.

No unknown-location sentinel or renderer is part of this decision.

## Alternatives

Owning source text in every diagnostic value was rejected because syntax and
compiled artifacts need cheap stable offsets, while source storage lifetime is
better owned by their enclosing compilation context.

Rune offsets and rune columns were rejected because jq's accepted behavior is
byte-oriented. A line table was deferred: the initial linear scan is small and
keeps the first contract minimal; an indexed implementation can replace it
without changing results or ownership.

Encoding unknown locations as a special span was rejected because the
corresponding compatibility evidence is disputed.

## Consequences

Future consumers are `syntax`, `program`, `compiler`, and `eval`. They may
carry `Span` values freely, but any call that resolves or renders a span also
requires the matching live `Source`. Their owning compilation/evaluation
objects must therefore establish a source-storage lifetime before adopting
this API.

Syntax should sequence span adoption after this proposal is accepted. Program
and compiler should then preserve those byte ranges without introducing a
second location type. Eval may consume preserved ranges only after program
ownership establishes access to the matching source. All callers rendering a
diagnostic must pass an allocator and free the returned string with the same
allocator.

This adds no project import edge: `diagnostic` continues to import no project
package.

## Validation

Unit tests cover first, middle, last, trailing-newline, and empty lines; empty
input; UTF-8 byte columns; multi-line and zero-width spans; EOF with and without
a trailing newline; end clamping; structurally invalid spans; accepted
in-range offsets copied into a span with a valid identity; same-length
different-source rejection by offset access, location, and rendering; copied
and equal-but-distinct source views; stale and inconsistent Source metadata;
the structural inability to reject consistently replaced public Source fields;
accepted fixture formatting; every allocation/resize failure point; exact-size
caller release; allocator leaks; and independence from borrowed and temporary
storage.

Required adversarial-review lanes: Odin ownership/safety and diagnostic
fixture/test-gap review.
