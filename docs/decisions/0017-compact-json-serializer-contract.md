# 0017: Compact JSON serializer ownership contract

- Status: proposed
- Date: 2026-08-02
- Workstream: json

## Context and evidence

jq's compact printer emits scalar spellings directly and separates container
items with commas and object keys from values with a colon, adding layout only
under the pretty flag (`upstream/jq/src/jv_print.c:218-307,312-382`). Native
object traversal uses the object's iterator rather than a sorted key set
(`upstream/jq/src/jv_print.c:312-345`; `upstream/jq/src/jv.c:1924-1952`).

Printing begins at indentation depth 0. Array elements and object values are
printed at their container depth plus one, and any term whose depth is greater
than `MAX_PRINT_DEPTH` 256 is replaced by the 19 raw ASCII bytes
`<skipped: too deep>` before kind dispatch (`upstream/jq/src/jv_print.c:19-21,
218-228,284-300,312-370,388-390`). Consequently a term at depth 256 prints
normally and one at depth 257 is skipped. An object at depth 256 still prints
each normally quoted key and colon before independently skipping its values;
the array/object loops then continue with later siblings
(`upstream/jq/src/jv_print.c:290-301,321-370`). The marker is not quoted or
escaped JSON string data.

String output is length-delimited: it obtains both a data pointer and byte
length, escapes quote, backslash, the five short JSON controls, all remaining
controls and DEL, and otherwise copies complete UTF-8 points
(`upstream/jq/src/jv_print.c:143-207`). The loop asserts if a malformed UTF-8
point reaches it, while jq string construction normally replaces malformed
input before storage (`upstream/jq/src/jv_unicode.c:29-82`;
`upstream/jq/src/jv.c:1112-1133`). The local `value.string_value` contract is
broader and can represent arbitrary bytes, so malformed UTF-8 requires an
explicit serializer error rather than a cstring rule or assertion.

With decimal support, jq prints the lazily generated `decNumberToString`
literal without trimming precision; infinities fall back to the native path
(`upstream/jq/src/jv.c:623-670`; `upstream/jq/src/jv_print.c:253-277`). Native
NaN becomes null, infinity is clamped to the largest finite binary64 value,
and dtoa chooses scientific notation from its decimal point and shortest-digit
count while retaining negative zero (`upstream/jq/src/jv_print.c:253-277`;
`upstream/jq/src/jv_dtoa.c:4200-4275`).

## Decision

`init_compact_serializer` binds a `Compact_Serializer` owner to its address and
explicit allocator. `serialize_compact` borrows a live `value.Value` and
produces an owned `Compact_Result` through an inert caller-provided result
address. `compact_result_bytes` returns a borrowed, length-delimited string;
the caller must destroy or move the result. Neither input nor output depends
on NUL termination, and no `context.temp_allocator` storage is used or escapes.

Both public owners have explicit invalid, ready, and cleanup-required states.
They are address-bound so ordinary copied structs are rejected before touching
owned memory. `take_compact_result` is the only supported move. Genuine
allocator `Free` failures preserve the owner and are retryable; a bulk
allocator's `Mode_Not_Implemented` retires the individual handle successfully.
Exact allocation lengths are required, and mismatched nonempty allocations
whose cleanup fails remain owned by the serializer.

Successful serialization and terminal failures without retained cleanup leave
the serializer ready for another call. A cleanup-required serializer rejects
serialization and remains destroy-only until every retained owner is retired;
genuine destroy failures preserve that state for retry. Results similarly
preserve their bytes across a genuine failed destroy.

Traversal uses an explicit growable frame stack. Frames own retained `Value`
handles obtained only through public Value APIs. Output uses a checked
growable byte buffer, transferred to the result on success. The serializer
does not consume the input and emits object members in Value iterator order,
which preserves insertion position when an existing key is updated.
Each frame also carries jq's logical print depth. A value frame deeper than
256 appends the raw marker without descending, then releases its retained
`Value` through the ordinary retryable frame-cleanup path. Parent frames stay
live, so later array elements and object members continue after a cutoff.

Malformed UTF-8 in a low-level Value string returns `Invalid_UTF8`. jq cannot
normally construct that state because its public string constructor
normalizes malformed input. This policy makes the difference explicit instead
of applying a cstring truncation or fabricating replacement behavior at print
time.

Literal formatting reconstructs jq's decimal printable coefficient from the
retained public spelling, including decimal-context overflow, underflow, and
rounding boundaries. The current Value API does not expose the private
normalized coefficient. Therefore an independently created future Value
implementation whose normalized decimal differs from the documented public
constructor rules would require a new Value accessor before exact printing;
the serializer does not broaden that shared contract. Original decimal
lexemes are intentionally not emitted verbatim: jq canonicalizes exponent and
decimal-point spelling while preserving coefficient precision.

No pretty, color, ASCII-only, sorted-key, or CLI-newline option is part of this
contract.

## Alternatives

- A recursive walk was rejected because jq-valid 10,000-frame inputs must not
  consume the native call stack.
- Returning a plain allocated string was rejected because it cannot preserve
  retryable `Free` ownership or detect an accidentally copied owner.
- Normalizing malformed bytes during serialization was rejected because the
  Value package does not promise jq string-constructor normalization.
- Adding a normalized-decimal accessor to Value was rejected as an unnecessary
  cross-workstream contract change for the existing constructor behavior.

## Consequences

Only `src/json` imports the existing `value` package. The new public API adds
no package edge and changes no Value contract. Direct consumers must keep the
serializer/result address and allocator backing live through final successful
destruction. Errors are structured and non-owning; cleanup ownership stays in
the serializer or result owner.

## Validation

Focused tests cover exact scalar, escaping, embedded NUL, UTF-8, decimal and
native number, insertion-order, empty/mixed/nested, copied-owner, reuse,
allocator failure/short/free-retry/bulk, and temporary-allocator behavior.
Depth tests cover terms immediately below, at, and above the 256 boundary;
raw marker bytes; keys and multiple skipped values at depth; later siblings;
and allocation and destroy retry cleanup. Bounded-stack probes cover 10,000
arrays, 5,000 keyed objects, and 6,000 alternating containers on an 8 MiB
stack, expecting jq's cutoff representation rather than unchanged nesting.
Required review lanes are source-aware semantic parity, Odin
ownership/resource safety, and test-gap analysis.
