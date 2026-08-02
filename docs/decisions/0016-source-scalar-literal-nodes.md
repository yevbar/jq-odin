# 0016: Source scalar literal nodes

- Status: proposed
- Date: 2026-08-02
- Workstream: language

## Context and evidence

The pinned lexer returns `+` and `-` as single-character tokens and matches a
numeric `LITERAL` without a leading sign. Its numeric rule accepts digits with
an optional fraction (including a trailing dot), a leading dot only when a
digit follows, and an optional exponent whose optional sign must be followed by
at least one digit (`upstream/jq/src/lexer.l:81,95-97`). Identifiers and fields
are matched as complete ASCII identifier units, so `nullfoo`, `truex`, and
`false_` are not keyword-prefix splits (`upstream/jq/src/lexer.l:129-131`).

`LITERAL` is a `Term`, while negative syntax is the separate recursive
`'-' Term` production. Its operand is the complete recursive `Term`, including
identity, field, postfix optional, grouping of a complete `Query`, and another
negation (`upstream/jq/src/parser.y:545-656`). Thus `--1` is two nested negative
terms around one unsigned numeric token. The bare `IDENT` action maps
exactly `false`, `true`, and `null` to constants; other identifiers are calls,
and the separate `IDENT '(' Args ')'` action remains a call
(`upstream/jq/src/parser.y:723-739`). The upstream compatibility suite directly
covers `true`, `false`, `null`, `1`, and `-1`
(`upstream/jq/tests/jq.test:5-29`).

Focused probes used jq 1.8.1 built from the pinned source checkout by
`tools/compat/build-oracle.sh`, SHA-256
`cc27ba973e95f459eb2979b39b9b923954b44c45c538184f44cc0f08df516d5d`.
They confirmed that `01`, `1.`, `.1`, `1e2`, `1e-2`, `.1E+2`, `-1`, `- 1`,
and `--1` compile; `nullfoo`, `truex`, and `false_` remain complete undefined
identifiers; and `1foo`, `1e`, `1e+`, `.1e+`, `1..2`, and `+1` fail at the
lexer boundaries described above. `1?`, `-1?`, `(-1).x`, `1,2|3`, and
`1|2,3` confirm that literal terms retain the existing postfix, field, comma,
pipe, and parenthesis grammar interactions.

Contextual-call probes confirmed that `true(.)`, `false()`, and `null(1)` do
not select the bare-keyword literal action. The same boundary holds with spaces
or newlines before `(` and when nested under unary minus, grouping, or optional.
The first and third forms reach undefined-function diagnostics, while the empty
`false()` Args form reaches a syntax diagnostic at `)`; none behaves as a
Boolean or Null literal followed by unrelated trailing input. This follows the
separate bare `IDENT` and `IDENT '(' Args ')'` productions
(`upstream/jq/src/parser.y:723-739`) and whitespace-skipping lexer rule
(`upstream/jq/src/lexer.l:129-135`).

The same pinned oracle compiled `-.`, `-.a`, `-(.)`, `-(.a)`,
`-(. | .)`, and `-(., .)`, including whitespace immediately after `-` and
inside groups. With input `{"a":2}`, `-.a` and `-(.a)` produce `-2`, while
identity, pipe, and comma variants reach runtime and report that the input
object cannot be negated. Direct `-.?` and `-.a?`, grouped `-(.a?)`, outer
optional `-(.a)?`, nested `--.`, `-(-.a)`, `--(. | .)`, and
`-(-(.a)?)` all compile. These observations agree with the general
`'-' Term` production and the recursive optional and grouping productions
(`upstream/jq/src/parser.y:564-580,640-656`). Filters beginning with `-` were
passed after `--` in every command.

Generated-parser boundary probes used the same source-built oracle. Unary
prefixes over `.` and `.a` accept 9,995 minuses and reject 9,996. Plain nested
groups accept 9,994 identity leaves and reject 9,995, while a deepest `. | .`
or `., .` Query accepts 9,993 surrounding groups and rejects 9,994 because the
operator adds one live parser-stack entry. A mixed 4,000 groups plus 5,995
inner minuses around `. | .` still compiles because those minuses reduce before
the pipe is shifted. These are observable consequences of the generated
parser's shared state/value/location stacks and 10,000-entry maximum
(`upstream/jq/src/parser.c:1690-1704,2247-2264,2320-2385`).

## Decision

Append the noncolliding public `Node_Kind` members `Null`, `Boolean`, `Number`,
and `Negate`. `Boolean` carries an Odin `bool`. `Number` carries the exact
length-delimited source bytes in an Odin `string`; it is never a `cstring` and
is not converted to a runtime float or `value.Value`. Because the sign is a
separate token, numeric text excludes it. Each separate minus becomes one
`Negate` whose child may be any `Term` form the current Odin syntax package
represents: identity, field, parenthesized identity/field/pipe/comma, scalar
keyword or number, nested negation, and their currently supported postfix
field/optional combinations. It spans from its own minus through its child and
wraps the completed postfix term, preserving `'-' Term` precedence. Thus
`--1` is an outer `Negate` spanning `[0,3)` whose child is an
inner `Negate` spanning `[1,3)`, whose `Number` child spans `[2,3)` and owns
exactly `"1"`.

Only a bare `true`, `false`, or `null` identifier becomes a scalar node. If the
next non-whitespace token is `(`, the parser preserves jq's contextual call
classification but returns the existing `Unexpected_Token` input result at
that opening delimiter before allocating a Boolean or Null node. Call AST and
lowering support are deferred to a separately owned contract change; this
decision does not claim that call spellings are accepted by the Odin subset.

Each numeric string is allocated with the Parser's captured allocator and is
owned by that address-stable Parser. A parser-private allocation registry is
the sole ownership and allocation-identity authority; the public, mutable
`Node.number_text` string header and `has_number_text` presence flag are only
AST payload views and are never consulted for cleanup. They may be changed by
callers without redirecting, suppressing, or duplicating a parser free. The
numeric text remains valid from successful parsing
until parser destruction begins, even if the caller releases the original
input bytes after parsing. Other node spans and field text retain their
existing borrowed-source lifetime. A caller that releases source backing must
not subsequently resolve spans or call `parser_source`; it may inspect the
owned numeric string and destroy the parser. Shallow Parser copies remain
forbidden. Every public Parser operation checks the initialized address
identity at runtime before inspecting, mutating, exposing, retrying cleanup of,
or freeing owned state; assertions after those guards are diagnostics only.
`parse_filter` returns `Misuse`, borrowed-view accessors return nil/zero views,
`init_parser` returns false, and destruction returns `Invalid_Argument` for an
invalid live copy. The same results apply to a copy-of-copy and to a live copy
used after the canonical owner is destroyed. Rejected copies never consult
their shared scanner, node arena, number registry, or pending numeric owner, so
the canonical Parser remains usable and retryably destroyable with assertions
disabled. An inert Parser may be moved before initialization, and heap
allocation is supported when initialization occurs at the Parser's final
stable address; a live Parser may not be moved.

Allocation failure leaves the partial number node in the Parser arena and
returns `Resource_Failure`. Exact-size allocation rejects nil or short success.
If retiring a malformed allocation fails, the Parser records that pending
owner for retry. Destruction releases pending malformed storage, each real
allocation recorded in the private registry, the registry storage, and then
the node arena. Each successful release clears only its private registry
record, so genuine free errors preserve that record for retry without replaying
prior releases; `Mode_Not_Implemented` retires it under the allocator's bulk
lifetime. Public node corruption, including substituted or aliased
pointer/length headers and independently changed presence flags, cannot affect
that iteration.

The `compiler` is a direct `Node_Kind` consumer owned by the program workstream.
This task has a narrow sequencing exception only to enumerate all four new
known node kinds in both existing lowering switches as intentional
`Invalid_AST`, with focused allocation-free rejection tests. Pre-allocation
validation accepts a structurally valid `Negate` payload and child reference
regardless of the child's supported source `Term` kind; lowering remains
deliberately unsequenced. Its pre-allocation
validation enforces the complete discriminant payload shape for every known
node kind: absent child, edge, name-span, boolean, and number fields retain
their exact zero state; required presence flags agree with their payloads; and
only a completed Number has a non-nil, positive-length `number_text` header with
`has_number_text` set. Incomplete Number nodes and stale payload left by a kind
swap are invalid. This does not alter scalar lowering or any other compiler
behavior. No Program instruction, evaluator behavior, package, or import edge
is added in this slice.

## Alternatives

- Borrowing the numeric token span was rejected because releasing caller input
  would dangle the requested numeric payload.
- Converting source text to a runtime float or `Value` was rejected because it
  loses spelling and violates the syntax package graph.
- Treating `-` as part of the numeric token was rejected because it contradicts
  the pinned lexer and grammar.
- Restricting negation to numeric or scalar operands was rejected because it
  contradicts jq's general `'-' Term` grammar and already represented grouped,
  identity, field, pipe, comma, and optional terms.

## Consequences

`syntax.Node_Kind` and `syntax.Node` change as shared contracts. The affected
packages are `syntax` and its direct `compiler` consumer. Program and evaluator
owners require a later accepted decision before scalar lowering is added.
`Parse_Outcome_Kind` gains `Misuse` so invalid Parser identity and lifecycle
calls remain distinct from input and allocator failures; the compiler's direct
test consumer checks only successful outcomes and requires no code change.
Numeric text adds one parser-owned allocation per number plus private registry
storage and therefore extends parser cleanup and allocator-failure coverage.
The compiler edits are the
explicitly delegated ownership exception above and must be replaced by a later
Program-owned lowering slice. The package graph is unchanged.

## Validation

Focused lexer/parser tests cover accepted integer, fraction, exponent, single
and repeated negative spellings; exact nested `--1` spans and unsigned `1`
ownership; rejected edge spellings and exact offsets; full identifier
boundaries; term precedence and postfix composition; caller-input release;
runtime shallow-copy and copy-of-copy rejection before and after canonical
cleanup, pending-number ownership, cleanup failure/retry, heap-address and
pre-initialization move semantics in assertions-disabled builds; exact-size,
short, failing, and retryable-free
allocators; caller corruption of public scalar pointer/length/presence fields,
unowned and aliased payloads, exact private-allocation counters, cleanup retry,
and non-scalar payload corruption; 10,000 nested negations with representative
identity, field, grouped pipe, and grouped comma leaves without native
recursion; and compiler shape acceptance followed by known `Invalid_AST`
without allocation. Run syntax
and compiler tests in default, debug, optimized, assertions-disabled, and ASan
modes with one and four threads, then `make validate` and `git diff --check`.
Request semantic-parity, Odin ownership/resource-safety, and parser test-gap
adversarial lanes.
