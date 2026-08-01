# 0008: Borrowed literal token contract

- Status: proposed
- Date: 2026-07-31
- Workstream: language

## Context and evidence

jq's numeric lexer rule has no sign and accepts digits with an optional dot,
or a dot followed by digits, followed by an optional complete exponent
(`upstream/jq/src/lexer.l:81,95-97`). Because flex chooses the longest match,
`.e0` and `.E1` are fields, `.E-1` and `.E+1` are a field followed by a
separate sign and number, and an incomplete exponent is not part of the
preceding number (`upstream/jq/src/lexer.l:95-97,129-130`;
`upstream/jq/tests/jq.test:172-177`). Official jq 1.8.1 probes additionally
confirmed `01`, `1.`, and `.1` as literals, and `1e`, `1e+`, and `.1e+` as a
literal followed by nonnumeric tokens. These observations are source facts,
not strict-JSON assumptions.

A quote enters the exclusive string state. That state returns distinct start,
text, interpolation-start, and end tokens; interpolation and ordinary
delimiters share flex's LIFO start-condition stack
(`upstream/jq/src/lexer.l:19-24,99-125,144-181`). Only the `)` that pops an
interpolation state returns the interpolation-end token. The generated EOF
rules return scanner EOF without synthesizing missing delimiters
(`upstream/jq/src/lexer.c:1482-1488,2661-2699`).

Escape candidates are grouped by
`(\\[^u(]|\\u[a-zA-Z0-9]{0,4})+` and passed, as one quoted fragment, to jq's
JSON parser; raw text instead goes directly through `jv_string_sized`
(`upstream/jq/src/lexer.l:104-125`). The parser wrapper diagnoses an invalid
text value at that complete token span (`upstream/jq/src/parser.y:145-160`).
Official jq 1.8.1 probes confirmed the resulting boundaries for invalid
`\\q`, short/nonhex Unicode escapes, invalid surrogate pairs, raw control
bytes, malformed UTF-8, a lone backslash, and embedded byte 0. In particular,
raw control bytes are accepted, malformed raw UTF-8 is accepted and later
normalized by `jv_string_sized` (`upstream/jq/src/jv.c:1112-1143,1278-1282`).

The parser passes both the source pointer and its explicit byte length to
`jq_yy_scan_bytes` (`upstream/jq/src/parser.y:956-965`). That generated entry
point copies all supplied bytes and appends two separate end-of-buffer markers
after the supplied length (`upstream/jq/src/lexer.c:2231-2248`). A byte 0
before that boundary therefore takes the generated DFA's real-NUL transition
rather than its EOF action (`upstream/jq/src/lexer.c:1515-1555,1794-1821`).
This matters for modules because the linker constructs their source locations
with `jv_string_length_bytes` (`upstream/jq/src/linker.c:330-358`). The current
top-level compile entry instead constructs its source length with `strlen`, so
its truncation occurs before the reusable lexer sees the source
(`upstream/jq/src/execute.c:1225-1229`).

The C lexer returns a token carrying a decoded `jv`. This syntax package may
not import runtime `value`, and decision 0004 requires tokens to remain
non-owning descriptions of the borrowed source.

## Decision

Replace the literal placeholders with `Number`, `String_Start`, `String_Text`,
`String_Interpolation_Start`, `String_Interpolation_End`, and `String_End`.
`Number` and `String_Text` carry a `value_span` equal to their full token span.
This span deliberately identifies the exact raw spelling, including escapes;
it is not a claim that escaped text has a contiguous decoded-value slice.
Decoding belongs to a later parser/literal layer and must use the matching live
source. No token owns or copies text.

The scanner validates escape candidates to jq's observable JSON-fragment
rules. A malformed candidate returns `Lexical_Error` at the exact candidate
span and consumes that candidate. This is an Odin interface design choice:
jq first returns an invalid `QQSTRING_TEXT` value and its parser wrapper then
reports the error at the same token span. Representing the already-known
failure as a lexical outcome avoids adding an owned decoded/error payload to
`Token` while preserving its observable boundary.

Raw string text is not UTF-8-normalized or JSON-control-validated by the
scanner. It remains one or more exact source bytes up to backslash, quote, or
the explicit source-length boundary; byte 0 is retained in that span. A later
decoder may reproduce jq's replacement behavior without changing token
boundaries.

The reusable scanner treats byte 0 according to the active lexer rule. In
normal and interpolation states it consumes one byte as `Lexical_Error`; in a
comment it is ordinary comment content; in raw string text it remains part of
`String_Text`; and immediately after a backslash it completes that escape
candidate, which the existing invalid-escape mapping reports at the complete
candidate span before scanning resumes. Numeric matching stops before byte 0,
after which the one-byte error is reported and later input is scanned. Only
source-length exhaustion returns repeatable `End_Of_Input`. Any future Odin
top-level driver that reproduces `jq_compile_args`'s C-string truncation must
apply that policy when constructing its `diagnostic.Source`, not inside this
explicit-length scanner.

The scanner's owned stack now records string, interpolation, and ordinary
delimiter states. Entry is allocation-atomic. Closers pop only a matching top
state; mismatches consume one byte as a lexical error without changing the
stack. EOF in any state returns repeatable `End_Of_Input`, retains unmatched
state until destruction, and emits no synthetic closing token or lexical
error. This follows the lexer boundary and deliberately leaves selection of
an unterminated-construct parser diagnostic to later parser work.

`destroy_scanner` returns `runtime.Allocator_Error`. Ordinary successful free
and `Mode_Not_Implemented` retire the scanner and make repeated destruction
allocator-free; the latter relies on the allocator's documented bulk lifetime.
Any other `Free` error leaves the complete scanner, its stack handle, and its
captured allocator unchanged, so the sole owner remains available for a later
destruction retry. This follows decision 0005's repository-wide premise that a
genuine allocator error means the allocation remains live. It fixes an
ownership defect in the original lexer commit, which ignored `delete`'s result
and erased the only pointer and allocator provenance after a failed free. No
token, scan-outcome, initialization, or scanning behavior changes.

## Alternatives

- Decoded owned token strings were rejected because they add allocation and
  duplicate source ownership.
- Treating jq literals as strict JSON was rejected because jq accepts leading
  zeros, trailing dots, raw control bytes, and other lexer-visible forms.
- Returning malformed escape text as a successful token with a separate
  validity payload was rejected because it expands the public token contract
  solely to emulate the C parser wrapper's two-step implementation.
- Synthesizing string or interpolation closers at EOF was rejected because the
  pinned lexer returns EOF and the parser owns unterminated syntax errors.
- Treating byte 0 as scanner-wide EOF was rejected because it confuses the
  top-level driver's `strlen` boundary with the explicit-length lexer contract
  used for module sources.
- Discarding a stack `Free` error and retiring the scanner was rejected because
  it loses the only retryable allocation handle. Panicking was rejected because
  it would make deterministic cleanup impossible in assertion-disabled builds.

## Consequences

The direct consumer is `src/syntax/lexer_test.odin`; no other current package
uses `Token_Kind`, `Token`, or `Scanner`. Future parser consumers must decode
`value_span` while the exact source and backing bytes remain alive. Syntax
continues to import only diagnostic, so the package graph does not change.
The stack allocation, allocator provenance, terminal resource-failure, and
live-scanner no-copy rules from decision 0004 remain unchanged. Existing
callers may continue to ignore a successful destructor result; callers using a
fallible allocator must keep the scanner and allocator backing state alive and
retry a reported genuine cleanup failure.

## Validation

- Official jq 1.8.1 explicit-length lexer and module probes cover every numeric
  boundary, field ambiguity, escape grouping, surrogate case, raw
  control/UTF-8 case, embedded-byte-0 state, mismatch, and unfinished state
  named above.
- Focused allocation-tracked tests assert token/value spans, nested LIFO
  interpolation, malformed escape spans, mismatch recovery, byte-0 continuation
  in every active state, repeatable true EOF, malformed raw UTF-8, every
  reachable allocation failure, and retryable stack destruction after an
  injected `Free` failure.
- Run syntax tests in default and debug modes, debug with AddressSanitizer when
  supported, then `make validate`.
- Request source-aware semantic-parity, Odin ownership/safety, and literal
  boundary/test-gap review lanes.
