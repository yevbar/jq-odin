# 0028: Default pretty JSON serializer contract

- Status: proposed
- Date: 2026-08-03
- Workstream: json

## Context and evidence

jq initializes CLI output with `JV_PRINT_INDENT_FLAGS(2)`, which combines
pretty output with two spaces per nesting level
(`upstream/jq/src/main.c:337`; `upstream/jq/src/jv.h:218-232`). For non-empty
arrays and objects, the printer writes a newline and child indentation before
each item, then a newline and parent indentation before the closer. Object
colons receive one following space. Empty containers remain `[]` and `{}`
(`upstream/jq/src/jv_print.c:284-307,312-377`). Color, ASCII-only strings, and
sorted keys are separate flags added by CLI option processing
(`upstream/jq/src/main.c:542-566`). The CLI adds its output newline after the
term printer returns (`upstream/jq/src/main.c:175-206`).

The scalar, depth, and ownership evidence already recorded by decision 0017
applies unchanged. In particular, strings are length-delimited and default
output preserves valid non-ASCII UTF-8 while escaping controls and DEL
(`upstream/jq/src/jv_print.c:143-207`), and a term deeper than 256 becomes the
raw marker before kind dispatch (`upstream/jq/src/jv_print.c:218-228`).

## Decision

Add the distinct public owner types `Pretty_Serializer` and `Pretty_Result`
and the procedures `init_pretty_serializer`, `serialize_pretty`,
`pretty_result_bytes`, `take_pretty_result`, `destroy_pretty_result`, and
`destroy_pretty_serializer`. `serialize_pretty` means exactly jq 1.8.1's
default two-space term formatting. It does not include the CLI's trailing
newline, color, ASCII-only output, or sorted keys. Those remain future option
boundaries rather than booleans on this API.

The pretty owners are representation-compatible but type-distinct wrappers
over decision 0017's compact owners. Both modes call one internal iterative
serializer with an explicit layout choice. This preserves the compact API and
ensures both modes have identical Value borrowing, address binding, allocator
ownership, retryable cleanup, result moves, UTF-8 validation, scalar spelling,
checked buffer growth, depth cutoff, and non-recursive traversal behavior.
Ordinary assignment of either pretty owner remains invalid; it does not create
a second owner.

Pretty indentation is emitted by the owned output buffer with checked
`depth * 2` arithmetic. Layout is added only for non-empty containers: before
every child/member, before the closing delimiter, and after object colons.
Empty arrays and objects receive no interior whitespace. The serializer does
not use `context.temp_allocator` and the result is independent of both the
input text buffer and the borrowed Value after the call completes.

## Alternatives

- A second copied serializer was rejected because it would duplicate the
  number formatter and resource-safety state machine.
- A public flags integer was rejected because color, sorting, and ASCII-only
  output are outside this slice and would expose unsupported combinations.
- Including the CLI newline was rejected because jq's term printer and process
  output framing are separate contracts.

## Consequences

The change stays within `src/json`, adds no import edge, and changes no Value
contract. Direct consumers choose compact or default-pretty mode by public API
and cannot accidentally exchange their distinct owner types. A future generic
printer option contract can replace the two entry points only through a new
shared-contract decision and coordinated consumer update.

## Validation

Focused tests pin exact jq 1.8.1 bytes for scalars, empty and nested
containers, insertion-order objects, decimal/native numbers, escaping,
Unicode, and embedded NUL. They also cover source lifetime independence,
serializer reuse, address-copy rejection, result moves, exact size overflow,
allocation-failure exhaustion, retryable serializer/result cleanup, the
256/257 depth boundary, and iterative 10,000-frame input. Run the JSON suite in
default, debug, speed, assertions-disabled, and ASan/LSan configurations with
one and four threads, then `make validate` and `git diff --check`.

Required adversarial lanes are source-aware printer semantic parity, Odin
ownership/resource safety, and test-gap review.
