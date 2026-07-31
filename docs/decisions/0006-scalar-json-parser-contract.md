# 0006: One-shot scalar JSON parser contract

- Status: proposed
- Date: 2026-07-31
- Workstream: json

## Context and evidence

jq's scanner recognizes only space, tab, carriage return, and line feed as
ordinary JSON whitespace (`upstream/jq/src/jv_parse.c:551-577,644-680`). Its
string decoder handles the JSON escapes, surrogate pairs, embedded escaped
NUL, and control-byte rejection before passing an explicit byte length to
`jv_string_sized` (`upstream/jq/src/jv_parse.c:446-503`). That constructor
replaces malformed UTF-8 points rather than treating the input as a C string
(`upstream/jq/src/jv.c:1112-1133,1278-1283`). The accepted evidence rows
`json-001` through `json-014` and `json-018` through `json-021` record these
behaviors and EOF distinctions.

Decision 0003 makes `value.Value` an opaque owning handle and requires
fallible constructors to return either one complete owned value or an inert
value. jq's JSON scanner does not impose RFC 8259 number grammar: after its
keyword routing it sends the accumulated literal to the numeric backend
(`upstream/jq/src/jv_parse.c:506-545`). With decimal-number support, that
backend accepts decNumber spellings and rejects only conversion syntax and
nonzero NaN payloads (`upstream/jq/src/jv.c:576-599`).

## Decision

`json.parse_scalar(input, allocator)` is a one-shot, explicitly scalar-only
API. It accepts exactly one `null`, boolean, jq/decNumber numeric literal, or
string, surrounded only by jq's four JSON whitespace bytes. Exactly one
complete UTF-8 BOM is accepted only at the document boundary. A partial BOM
prefix exhausted at final EOF produces `Expected_Value`, with detection at the
last observed byte and cause at the EOF boundary. `Malformed_BOM` requires an
actually observed mismatching suffix byte. A second BOM is ordinary input and
is rejected by normal literal classification. jq strips the BOM
before scanning (`upstream/jq/src/jv_parse.c:722-752,772-775`). Arrays,
objects, missing values, trailing input, syntax failures, allocation failures,
size overflow, and unexpected Value-constructor failures have stable distinct
error kinds. It is not an incremental parser and does not accept a sequence of
values.

The input is a borrowed, length-delimited Odin string for the duration of the
call. No returned object aliases it. The error contains no view into the input
and keeps two semantically distinct locations. `detection_offset` is the
zero-based absolute byte whose consumption triggered validation: the delimiter
for a delimiter-terminated literal, the closing quote for a matched string, or
the last observed byte when EOF triggers validation. `cause_offset`, when
`has_cause_offset` is true, is the zero-based absolute locally offending byte
or an EOF boundary such as `len(input)` for a truncated exponent. Constructor
and allocation failures use the first byte of the value for both locations.

A jq-facing diagnostic renderer derives one-based line and column locations by
replaying jq's byte scanner through `detection_offset`: increment the column
for each consumed byte, then increment the line and reset the column to zero on
LF (`upstream/jq/src/jv_parse.c:644-649`). A stripped leading BOM is skipped
without advancing that scanner cursor, while both stored offsets remain
absolute in the original input. Thus single-line, no-BOM errors use
`detection_offset + 1`; the distinct local cause never substitutes for the jq
cursor.

On success the result is one complete owning `value.Value`, with all payload
storage allocated through the explicit caller allocator and carrying the
Value package's allocator provenance. The caller must transfer or destroy it
with the Value ownership API. On every parse or construction failure the
returned Value is inert. Decode scratch uses `context.temp_allocator` and is
retired before every ordinary return; allocation failure at either the
temporary decode or owning-Value stage has the same stable allocation error
kind. A successful `runtime.mem_alloc` result is usable only when its returned
slice length exactly equals the requested capacity. Nil/no-error and
undersized/no-error results are allocation failures. A nonempty mismatched
slice is retired through the same cleanup path, so a genuine `Free` failure
transfers its live handle into the retryable exceptional error rather than
losing it. The active temporary allocator and all of its backing state must
remain valid for the duration of the call. Scratch survives only by explicit
transfer to the exceptional cleanup error described below, or where an
allocator's documented bulk lifetime makes individual `Free` a retirement
operation.
The caller must keep the allocator and its reachable backing state alive until
the returned Value and all clones are finally destroyed. Allocator callbacks
must obey Odin's contract, including that an error from `Free` means the
allocation remains live.

Ordinary parse errors are non-owning. If individual retirement of decode
scratch or a mismatched Value-constructor allocation reports a genuine `Free`
error, parse returns an inert Value and `Scratch_Cleanup_Failure`; that
exceptional error owns the scratch allocation, Value-constructor error, and any
Value already constructed from scratch. Its `cause_kind` records a
construction failure when cleanup superseded one. The owning error must not be
copied. The caller must retry
`destroy_scalar_parse_error` while keeping all recorded allocators alive. The
destroy procedure attempts both retirements, retains each handle whose `Free`
still fails, and becomes inert only after all storage is retired. This makes a
temporary failure observable without leaking, and prevents a persistent
failure from losing the only retryable handles. `Mode_Not_Implemented` is a
successful individual retirement for an allocator whose storage is released
in bulk.

Numeric validation may construct an owning Value before trailing input is
classified. That Value is retired before returning `Trailing_Input`. If its
allocator reports a genuine `Free` error, the existing
`Scratch_Cleanup_Failure` representation retains the Value without scratch and
records `Trailing_Input` in `cause_kind`; the same retry rules apply.

Keyword routing follows jq's scanner: leading `t` and `f`, plus leading `nu`,
must match their exact keywords; every other non-keyword literal is routed
through `value.literal_number_value`, with no RFC-strict pre-gate. The literal
is validated and constructed when its delimiter or EOF is detected, before a
completed scalar is checked for trailing input. Thus an invalid numeric token
followed by more input is `Invalid_Number` at that detection cursor, while only
a valid completed scalar can become `Trailing_Input`. The Value retains its
owned number spelling and decimal identity according to decision 0003. For
numeric conversion only, an embedded NUL terminates the spelling passed to the
numeric constructor while the scanner still consumes the full length-delimited
token. This preserves jq's observable C-string numeric quirk without applying
it to keywords or strings
(`upstream/jq/src/jv_parse.c:506-545,667-680`). String decoding preserves
escaped NUL, combines valid UTF-16 surrogate pairs, maps a lone low-surrogate
escape through jq's malformed-UTF-8 replacement behavior, and replaces
malformed raw UTF-8 using jq's invalid-sequence consumption boundaries within
the single supplied buffer. Bytes `C0`, `C1`, and `F5` through `FF` are invalid
single-byte points, so each is replaced independently; valid multibyte lead
classes retain jq's truncated, noncontinuation, overlong, surrogate, and
above-range consumption rules (`upstream/jq/src/jv_utf8_tables.h:2-18`,
`upstream/jq/src/jv_unicode.c:29-74`). If scanning reaches final EOF without a
closing quote, the result is unconditionally `Unfinished_String`, with
detection at the last observed byte and cause at the EOF boundary. Escape,
Unicode, control-byte, surrogate, and malformed-UTF-8 validation occurs only
after a closing quote is observed (`upstream/jq/src/jv_parse.c:446-503,694-704,
823-833`).
String decode scratch is bounded by three times the bytes between the matched
quotes, with checked multiplication; trailing whitespace or other input after
the matched quote cannot increase that allocation.

## Alternatives

- An RFC 8259 numeric pre-gate was rejected because jq-facing parsing delegates
  non-keyword literals to its broader numeric backend; rejecting leading plus,
  leading zero, or open decimal-point forms would contradict jq 1.8.1.
- Returning an input-backed string view was rejected because the Value must
  outlive temporary input buffers safely.
- Returning allocated diagnostic text was rejected for this kernel because it
  would add a second lifetime and obscure the guaranteed inert result on
  failure.
- Calling the API `parse` or accepting containers partially was rejected so
  later container and incremental-stream contracts can be added honestly.

## Consequences

The decision adds only the documented `json -> value` import edge. `json` owns
the scalar parser and its focused tests; `value` remains the sole owner of
runtime Value representation and final destruction. Future container and
streaming APIs may reuse internal scanning rules but must record their own
state, ownership, and partial-buffer lifetime contracts.

## Validation

- Allocation-tracked scalar, jq/decNumber grammar, escape, Unicode, numeric and
  string NUL, BOM, malformed UTF-8, whitespace, EOF, trailing-input, and
  unsupported-container tests.
- Allocation-failure sweep and caller-allocator provenance tests, including
  nil/no-error and short/no-error scratch results, successful mismatch cleanup,
  retryable mismatch cleanup failure, and take/destroy behavior.
- Focused differential probes use the official jq 1.8.1 Linux AMD64 release
  binary, reporting `jq-1.8.1` with SHA-256
  `020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`.
  They cover permissive numeric spellings, numeric-only NUL-prefix conversion,
  keyword/string NUL separation, delimiter/EOF detection columns, and complete,
  partial, mismatched, and repeated BOM inputs.
- Debug and AddressSanitizer JSON tests with fail-on-bad-memory, relevant Value
  plus JSON tests, and `make validate`.
- Fresh semantic-parity and Odin ownership/safety adversarial review lanes.
