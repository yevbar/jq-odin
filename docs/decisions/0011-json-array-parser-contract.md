# 0011: One-shot JSON array parser contract

- Status: proposed
- Date: 2026-08-01
- Workstream: json

## Context and evidence

jq's ordinary parser keeps each open container as an owning stack entry. A
completed scalar is first held in `next`; comma and closing-bracket transitions
transfer that value into the current array, and closing an array transfers the
array back through `next` (`upstream/jq/src/jv_parse.c:98-114,125-215`). The
same transition table distinguishes a comma without a value, a trailing comma,
a missing separator, an unmatched closer, and a colon outside an object
(`upstream/jq/src/jv_parse.c:125-143,156-215`). At final EOF, nonempty container
state produces `Unfinished JSON term` before the one-shot wrapper classifies an
empty result (`upstream/jq/src/jv_parse.c:823-860,864-900`).

jq arrays own their stored `jv` handles, release every element on final backing
release, begin with capacity 16, and append by consuming the array and element
through set (`upstream/jq/src/jv.c:821-855,990-1042`). Decision 0007 translates
that behavior into the opaque `value.Value` array API. JSON must therefore use
`array_append_take`, retain no private slot pointer, and handle the returned
displaced owner and `Array_Operation_Error` even though a newly built parser
array normally has no displaced element.

Bounded probes used the official jq 1.8.1 Linux AMD64 binary, reporting
`jq-1.8.1` and SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`:

```sh
printf '%s' '[]'       | /tmp/jq-1.8.1 -ce .
printf '%s' '[1,]'     | /tmp/jq-1.8.1 -ce .
printf '%s' '[,1]'     | /tmp/jq-1.8.1 -ce .
printf '%s' '[1,,2]'   | /tmp/jq-1.8.1 -ce .
printf '%s' '[[1]'     | /tmp/jq-1.8.1 -ce .
printf '%s' '[1 2]'    | /tmp/jq-1.8.1 -ce .
printf '%s' '["a" "b"]' | /tmp/jq-1.8.1 -ce .
printf '%s' '[1}'      | /tmp/jq-1.8.1 -ce .
/tmp/jq-1.8.1 -n --arg s '[] 2' '$s|fromjson'
/tmp/jq-1.8.1 -n --arg s '[] 1e+' '$s|fromjson'
/tmp/jq-1.8.1 -n --arg s '[] [1,]' '$s|fromjson'
/tmp/jq-1.8.1 -n --arg s '[] {' '$s|fromjson'
for depth in 9999 10000 10001; do
  perl -e 'print "[" x $ARGV[0], "null", "]" x $ARGV[0]' "$depth" |
    /tmp/jq-1.8.1 -e . >/dev/null
done
perl -e 'print "[\"", "[" x 10001, "\"]"' | /tmp/jq-1.8.1 -e . >/dev/null
perl -e 'print "[" x 10000, "{"' | /tmp/jq-1.8.1 -e . >/dev/null
```

They produced an empty array; `Expected another array element` at column 4;
`Expected value before ','` at columns 2 and 4; unfinished-container EOF at
column 4; missing-separator errors at columns 5 and 8; and the jq object-pair
diagnostic at column 3 for the mismatched closer. These probes establish scanner
detection positions, not a promise that this package renders jq's diagnostic
strings. The later-input probes produced `Unexpected extra JSON values`, an
invalid number at EOF column 6, a trailing-comma error at column 7, and an
unfinished object at EOF column 4. Depths 9,999 and 10,000 succeeded; 10,001
failed with `Exceeds depth limit for parsing` at column 10,001. A shallow array
whose string contains 10,001 opening brackets succeeded, while 10,000 open
arrays followed by an object opener failed at the same depth boundary.

## Decision

`json.parse_value(input, allocator)` is the smallest one-shot complete-value
API above `parse_scalar`. It accepts one scalar or an array recursively composed
of null, booleans, numbers, strings, and arrays. It accepts jq's four whitespace
bytes and one document-boundary BOM under decision 0006. Objects return
`Object_Not_Supported` at their opening brace, including when nested. Object
parsing, streams, printing, CLI behavior, and jq filter syntax remain outside
this slice. `parse_scalar` remains source- and behavior-compatible and continues
to reject arrays as `Array_Not_Supported`.

The result and error types remain `value.Value` and `Scalar_Parse_Error`; this
avoids a second ownership/error family while retaining the existing scalar API.
The error-kind enum distinguishes unfinished arrays, expected elements, value
before separator, missing separators, unmatched array and object closers,
object key/value-pair state, a missing string key before a colon, a colon after
a pending non-object value, extra valid JSON values, the container depth limit,
and array-operation failure. Detection offsets follow the scanner byte that
establishes the failure; cause offsets identify the local token start or EOF
boundary.

`parse_value` applies jq's one-shot second-result precedence. After one complete
value it scans one later value: a second valid value returns
`Unexpected_Extra_Values` at that value's first byte, while a later syntax,
depth, or unsupported-object error supersedes the completed value. It does not
collapse every remainder into `Trailing_Input`. `parse_scalar` retains its
earlier scalar-only contract and error behavior.

Parsing uses an explicit temporary frame stack sized from the maximum syntactic
array nesting outside quoted strings, capped at jq's 10,000-container limit.
The 10,000th active array is accepted; another array or object opener is rejected
with `Depth_Limit` at that opener. Each active frame owns one independent partial
array. Closing a nested frame transfers its array through `array_append_take`; a
successful append leaves the frame inert. Scalar parsing reuses the decision-0006
scanner, decoder, numeric constructor, UTF-8 normalization, escape, embedded-NUL,
and offset rules. Returned Values contain only Value-owned storage and retain no
input or frame slice.

The caller allocator supplies every returned scalar and array payload. The
active `context.temp_allocator` supplies only parser frames and scalar decode
scratch and must remain valid through the call. Exact-length allocation is
required. Nil/no-error, short/no-error, explicit allocation failure, and checked
size overflow return stable failures. `Mode_Not_Implemented` on Free is
successful retirement under a bulk-lifetime allocator.

On an ordinary failure, the parser destroys every pending scalar and active
partial array and then retires frame and decode scratch. If a genuine Free error
prevents any cleanup, the returned Value is inert and the parse error becomes
`Scratch_Cleanup_Failure`. It may own scalar scratch, a Value constructor error,
an array-operation error, one independent Value, and the typed frame allocation
containing any partial arrays whose recursive destruction must resume. The
error is a non-copyable owning handle. `destroy_scalar_parse_error` retries all
owners, leaves only failed owners live, and frees the frame allocation only
after every frame Value is inert. The allocator and all reachable backing state
must outlive every retry.

## Alternatives

- A recursive Odin call-stack parser was rejected because deeply nested input
  would make native stack capacity an undocumented parse limit and would not
  provide storage for an unbounded set of independently retryable partial-array
  owners.
- Reaching into Value array slots or backing capacity was rejected because it
  violates decision 0007 and would retain pointers across growth.
- A separate public array parse-error type was rejected because scalar and array
  construction share the same one-shot ownership and cleanup paths.
- Accepting objects partially was rejected because it would create an API whose
  success grammar exceeds this implementation slice.

## Ownership and package effects

This changes no import edge or Value contract. `json` continues to import only
the already permitted `value` package. The new public parse API and the extended
cleanup state affect future direct JSON consumers, which must treat a
`Scratch_Cleanup_Failure` error as non-copyable and retry its destruction before
retiring allocator state. No consumer may inspect or mutate a Value payload.

## Validation

- Focused tests cover empty, flat, nested, 9,999/10,000/10,001-deep, BOM,
  brackets inside strings, mixed array/object depth, whitespace, string,
  malformed UTF-8 normalization, escaped and literal NUL, number, missing
  separator/value/closer, duplicate/trailing separator, distinct root and array
  punctuation, later-input precedence, and nested unsupported-object cases.
- Allocation-tracked tests sweep caller allocation failure through nested array
  creation, scalar construction, capacity growth, and cleanup; separately cover
  exact frame allocation, failed frame Free, nested recursive teardown retry,
  and arena/bulk retirement.
- Run strict optimized, debug, debug with ASan/LSan, and assertions-disabled
  JSON tests with memory tracking and fail-on-bad-memory, followed by
  `make validate` and bounded jq 1.8.1 probes.
- Request fresh source-aware semantic-parity, Odin ownership/safety, and
  allocation/failure-injection test-gap review lanes.
