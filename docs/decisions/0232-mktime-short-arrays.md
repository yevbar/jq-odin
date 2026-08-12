# Decision 0232: bounded short `mktime` arrays

Status: proposed, 2026-08-12.

jq zero-initializes `struct tm` and copies only the datetime-array fields that
are present before UTC normalization (`upstream/jq/src/builtin.c:1605-1633,
1661-1672`). Thus `[2024]` and `[2024,8]` leave the day at zero and normalize
to 2023-12-31 and 2024-08-31 respectively.

The evaluator accepts one- and two-field numeric arrays. It supplies day one
to Odin's range-checked component constructor and subtracts one UTC day from
the result, reproducing the bounded zero-day normalization without adding a
package, import edge, opcode, or public type. Empty arrays and general C
`timegm` overflow normalization remain deferred.

The parser and compiler retain the existing append-only `Mktime` node and
opcode. The input array remains borrowed by `mktime_result`; it copies numeric
fields and allocates no storage. `compat/mktime.jq.test` and focused syntax,
compiler, and evaluator tests cover the slice. A semantic-parity review should
probe one- and two-field arrays around month and year boundaries.
