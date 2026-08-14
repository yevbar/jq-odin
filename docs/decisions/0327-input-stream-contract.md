# Decision 0327: shared input-stream contract for `input`

- Status: proposed
- Date: 2026-08-14
- Workstream: cli/eval integration

## Context and evidence

The pinned jq compatibility fixture labels `input/0` as a stream operation and
uses `try input catch .` at `upstream/jq/tests/jq.test:2293-2297`. With one
top-level `null` input, jq consumes the next stream item at EOF and emits the
catchable string `"break"`. This is distinct from an empty top-level stream,
where the filter is never started and no output is produced. A second stream
value is consumed normally; malformed JSON in that value is a catchable input
error when `input` is inside `try`.

The jq runtime stores an input callback and its opaque state on the evaluator at
`upstream/jq/src/execute.c:47-53`; the public setter/getter are at
`upstream/jq/src/execute.c:1287-1295`. The CLI installs
`jq_util_input_next_input_cb` before processing values at
`upstream/jq/src/main.c:654-672`, so `input` shares the same ordered source
cursor as the outer processing loop and can cross input-file boundaries.

The Odin CLI currently frames one JSON text at a time in
`cmd/jq-odin/main.odin:722-1000`, drains framed values in
`cmd/jq-odin/main.odin:1008-1110`, and reads each source in
`cmd/jq-odin/main.odin:1116-1134`. It then invokes `run_input` once per framed
value at `cmd/jq-odin/main.odin:436-472`. The driver API accepts one borrowed
`json_input` string per call at `src/driver/package.odin:982-990`; its
`Run_Result` owns one current `value.Value` at
`src/driver/package.odin:497-515`. The parser rejects an unrecognised
identifier at `src/syntax/parser.odin:1549-1552`, and the current program/eval
contracts have no `Input` node or opcode.

## Decision

Add a stream-provider boundary that lives for one CLI invocation, above the
per-value `Run_Result` lifetime. The provider is the sole owner of the ordered
cursor over framed JSON values and source transitions. The CLI remains
responsible for byte framing, BOM/whitespace handling, source paths, line
numbers, and read errors; it exposes completed values and source metadata to the
provider instead of teaching the evaluator about files or descriptors.

The evaluator receives a borrowed provider callback/data pair (or an equivalent
`eval`-owned interface) and requests at most one next value for each execution
of an `Input` opcode. A successful request transfers an owned `value.Value` to
the evaluator; provider storage must not retain a slice into a temporary input
buffer. The provider state persists while the filter yields, resumes, catches,
or backtracks, so a consumed value is not replayed by a later continuation.

Provider outcomes are explicit:

1. `Value`: return the next JSON value in argv/stdin order, including crossing
   from one input path to the next.
2. `EOF`: raise a catchable runtime error whose observable value is the string
   `break`. EOF is not a process error; an uncaught `input` EOF remains jq's
   runtime status 5.
3. `Parse_Error`: raise a catchable runtime input error carrying jq's parser
   message and source location. The cursor becomes terminal for that source
   sequence and must not silently retry malformed bytes.
4. `IO_Error`: preserve a non-catchable process/input-I/O failure with its
   existing CLI status and cleanup path. The exact jq status/diagnostic remains
   part of the CLI compatibility fixture.

The initial top-level stream and the provider are separate concepts. With no
top-level value, the filter is never started; with `-n`, the initial filter
input is synthetic `null` but the provider still reads the real input stream.
This preserves the jq distinction demonstrated by the fixture and avoids
making `-n` disable `input`.

The syntax workstream owns recognition of the zero-argument `input` builtin and
its source span. The program/compiler workstream owns the `Input` instruction
and validates that it has no operands. The eval workstream owns continuation,
provider outcome mapping, and cleanup of transferred values. The driver/CLI
workstream owns the provider implementation, framing/source transitions, and
the invocation lifetime. `eval` must not import `driver`; the callback contract
must remain dependency-direction-safe.

## Alternatives

* Rewriting the exact source string `try input catch .` in the driver was
  rejected: it cannot preserve second-value consumption, empty-stream
  cardinality, `-n`, malformed-input catches, or file-boundary ordering.
* Adding a process-global stdin reader was rejected: it violates invocation
  ownership, makes concurrent embedders unsafe, and cannot model argv source
  transitions or retryable cleanup.
* Passing a complete preloaded JSON array to each evaluator was rejected: it
  changes streaming/memory behavior and loses the one-value-at-a-time
  continuation semantics of `input`.

## Consequences

The change is a shared contract across `syntax`, `program`, `compiler`, `eval`,
`driver`, and `cmd/jq-odin`; implementation must update direct consumers and
focused tests together. The provider owns framed source buffers until a value
is transferred, then the evaluator owns that value. Every terminal, catch, and
allocator-retry path must release or retain the provider/evaluator owner
explicitly. Existing per-value `run_with_options` callers remain valid for
filters that do not use `input`; a stream-aware entry point or option is needed
for the new opcode.

## Validation

The implementation must add oracle-backed cases for: empty stdin; one value at
EOF; two values; `-n 'input'`; malformed second value under `try`; malformed
second value without `try`; multiple files and `-` transitions; and repeated or
generator execution of `input`. Required review lanes are source-aware
semantic-parity, Odin ownership/safety, and CLI stream/error test-gap review.
