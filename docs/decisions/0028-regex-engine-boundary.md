# 0028: Regex engine boundary and foreign-library policy

- Status: proposed
- Date: 2026-08-03
- Workstream: specialty

## Context and evidence

jq exposes only one native evaluator primitive, `_match_impl/4`
(`upstream/jq/src/builtin.c:1947`). It validates input, pattern, and modifier
types, maps eight flags, compiles with `ONIG_ENCODING_UTF8` and
`ONIG_SYNTAX_PERL_NG`, searches into byte-span regions, and converts those
spans to jq match records (`upstream/jq/src/builtin.c:910-1109`). The public
`match`, `test`, `capture`, `scan`, `splits`, `split`, `sub`, and `gsub`
semantics are jq-coded generator wrappers above that primitive
(`upstream/jq/src/builtin.jq:80-130`).

The build can use system or bundled Oniguruma, fall back to the bundled source,
or disable regex (`upstream/jq/configure.ac:239-284`). The pinned compatibility
baseline uses bundled commit `4ef89209a239c1aea328cf13c05a2807e5c146d1`.
The CLI also changes Oniguruma process-global state by setting parse depth to
1024 (`upstream/jq/src/main.c:301-310`). Pattern syntax, selection, named-group
behavior, error text, and resource boundaries are consequently foreign-engine
behavior, not replaceable by a generic regular-expression API.

The fixture baseline requires codepoint rather than byte offsets, preserves
combining codepoints as separate units, distinguishes unmatched from
participating-empty groups, and preserves left-to-right generator order
(`upstream/jq/tests/onig.test:1-77`; `upstream/jq/tests/manonig.test:18-54`).
Substitution and splitting add evaluator/generator semantics above matching
(`upstream/jq/tests/onig.test:80-210`). Invalid external UTF-8 is normalized to
U+FFFD when a jv string is constructed, before it reaches regex
(`upstream/jq/src/jv.c:1112-1133,1278-1282`).

## Decision

### Dependency direction

After coordinator acceptance and a package-graph update, create a leaf engine
boundary owned by specialty. Production dependencies must point:

```text
eval -> regex -> regex/onig (foreign C binding)
  |       |
  v       v
value  diagnostic
```

`regex` must not import `eval`, `program`, `compiler`, `syntax`, `json`, or
`value`. Its public contract uses borrowed length-delimited UTF-8 pattern and
subject bytes, scalar flag bits, owned compiled-pattern handles, a byte-indexed
search cursor, and neutral match/capture records containing byte positions and
participation state. A search cursor is not a UTF-8 slice boundary: jq can pass
an interior byte after a zero-width match. Likewise, an empty result position
may be interior to a codepoint. A participating nonempty match or capture is a
byte range whose two endpoints must be UTF-8 boundaries; an unmatched capture
uses an explicit sentinel rather than a byte range. The eval owner converts
the raw byte positions to jq codepoint offsets and constructs `value.Value`
objects. Evaluator-owned jq-coded builtin programs implement `match`, `test`,
`capture`, `scan`, `splits`, `split`, `sub`, and `gsub`; the specialty package
does not own generator or replacement-filter execution.

This edge is proposed, not active. No package may be added until the
integration coordinator accepts this decision and updates
`docs/architecture/package-graph.md` and root build ownership.

### Transitional foreign-library policy

The first implementation must bind only the repository-pinned bundled
Oniguruma source. System Oniguruma discovery is forbidden for compatibility
runs because version-dependent syntax, Unicode tables, matching, and error
messages are observable. The C binding is private under `src/regex/onig/**`;
no `OnigRegex`, `OnigRegion`, `UChar*`, numeric Oniguruma error code, allocator,
or process-global configuration call crosses into eval.

Initialization sets the parse-depth limit once in driver-controlled startup,
before concurrent regex use. Tests must not mutate this global limit in
parallel. Pattern and subject data cross the boundary as `(pointer, length)`;
conversion through `cstring` is prohibited, preserving embedded NUL. The
binding borrows both spans only for a synchronous call. A compiled handle owns
exactly one `regex_t*`; a search result copies all region offsets before region
reuse; error text is copied into Odin-owned storage before return. Destruction
is explicit and idempotence is not assumed.

### Final foreign-library policy

Bundled pinned Oniguruma remains the required production engine for the jq
1.8.1 compatibility milestone. Shipping a different system version or a
different regex engine is not a supported final configuration. The optional
no-Oniguruma jq build is represented only as a separately tested feature mode
with jq's exact unavailable-library error; it must not silently select a
different engine.

A future pure-Odin engine may replace the foreign dependency only through a
new accepted decision after it passes the entire regex inventory, exact error
and resource-boundary cases, and dialect/Unicode differential fuzzing against
the pinned oracle. The neutral `regex` contract must not expose Oniguruma
layout, so such replacement does not alter eval.

### Ownership at the Odin/C boundary

- The caller borrows pattern and subject storage for the duration of compile or
  search; C stores neither subject pointer nor temporary error buffer.
- A successful compile transfers one opaque owned handle to the Odin regex
  wrapper. Failed compile returns no live handle.
- Each search owns one region scratch object internally. Match and capture byte
  spans are copied to Odin-owned records before scratch reset or destruction.
- Search cursors and participating empty-result positions are bounded byte
  positions and may point inside a multibyte codepoint. They are preserved
  exactly, not rounded to a UTF-8 boundary.
- Every participating nonempty match or capture range is bounds-checked and
  both endpoints are validated as UTF-8 boundaries before its bytes can be
  exposed. This validation does not apply to an empty position or the
  unmatched-capture sentinel.
- Named-capture bytes are copied during `onig_foreach_name`; callback pointers
  never escape the callback.
- The caller supplies the allocator for every Odin-owned compiled wrapper,
  copied name, error, and result array. Foreign destruction completes before
  that backing allocation is released.
- The eval adapter borrows neutral records only while converting byte spans to
  codepoint offsets and constructing independently owned jq values.

## Separable implementation tasks and owned paths

These tasks are intentionally ordered only where a dependency exists and have
non-overlapping write ownership:

1. `regex-onig-binding`: `src/regex/onig/**`; private declarations, pinned
   build/link prototype, global initialization, compile/search/free wrappers,
   acceptance of bounded interior-byte search cursors, exact copying of raw
   region positions, and C-boundary failure tests.
2. `regex-neutral-contract`: `src/regex/**` excluding `src/regex/onig/**`;
   flags, opaque compiled owner, neutral match records, distinct invariants for
   arbitrary empty byte positions versus UTF-8-aligned nonempty ranges, and
   focused unit tests. This consumes task 1 without exposing foreign types.
3. `regex-eval-primitive`: `src/eval/regex_primitive/**`; `_match_impl`
   adaptation, jq-compatible conversion of raw empty positions to codepoint
   offsets, one-byte zero-width restart, value construction, type/errors, and
   ordered match/test behavior. This starts after tasks 1 and 2.
4. `regex-wrapper-programs`: `src/eval/regex_builtin/**`; evaluator-owned
   jq-coded public wrapper definitions and evaluator fixtures. This depends on
   the agreed primitive signature and may proceed alongside task 3 after
   integration assigns the evaluator path. The compiler workstream may consume
   these definitions through its existing interfaces, but does not own or
   duplicate them.
5. `regex-compat-adapter`: `tools/compat/regex/**` and
   `compat/regex-cases.json`; fixture discovery, binary-input catalog,
   oracle/candidate comparison including multibyte empty-match cardinality,
   offsets, captures and nonempty ranges, and report tests. It may proceed
   alongside tasks 1-4 under the compat owner.
6. `regex-differential-fuzz`: `compat/regex-fuzz/**`; bounded pattern/subject
   corpus and exact oracle/candidate reducer. It starts after task 5 and does
   not edit implementation paths.

The path assignments above become active only when the coordinator records
them in `docs/workstreams.md`; this proposal does not unilaterally transfer
current eval, compiler, compat, root-build, or architecture ownership.

## Alternatives

- Importing regex directly into `value` was rejected because matching is an
  evaluator operation and would make the foundational value package depend on
  a foreign engine.
- Returning jq `Value` objects from the engine was rejected because it reverses
  the dependency and couples an engine replacement to value ownership.
- Reimplementing all public wrappers inside `regex` was rejected because scan,
  split, and substitution depend on jq generators and replacement filters.
- Using Odin or libc NUL-terminated strings was rejected because jq strings and
  regex patterns are length-delimited and can contain U+0000.
- Accepting any installed Oniguruma was rejected because versioned syntax,
  Unicode data, diagnostics, and limits form part of the observable oracle.
- Selecting a simpler native engine was rejected because jq specifies the
  Perl-NG Oniguruma dialect, named-group behavior, flags, and selection rules.

## Consequences

The initial package graph gains two one-way edges only after coordinator
acceptance: eval may import regex, and regex may import its private onig package
and diagnostic. Root build and distribution work must compile the pinned C
source and make the optional feature mode explicit. The CLI/driver owner must
coordinate one-time engine initialization before evaluator concurrency.

The neutral contract intentionally preserves raw byte positions. This keeps
jq-specific codepoint counting with the eval adapter and preserves the foreign
result exactly. It must not impose one UTF-8-boundary rule on all positions:
bounded search cursors and participating empty match/capture positions may be
inside a multibyte codepoint, while every participating nonempty range must
still have UTF-8-aligned endpoints after jv-compatible U+FFFD normalization.

After a zero-width match jq restarts at `region->end[0] + 1` byte and continues
while that cursor is at most the subject end (`upstream/jq/src/builtin.c:1007-1036,1103`).
For an empty position, jq counts complete decoded codepoints while the decoding
pointer is less than the raw position (`upstream/jq/src/builtin.c:1009-1016`).
Consequently the two-byte subject `é` searches from byte positions 0, 1, and 2
and externally reports offsets `[0,1,1]`; the last two distinct raw positions
map to the same visible codepoint offset. Advancing by codepoint, rejecting the
interior cursor, rounding it, or deduplicating the visible records is a
compatibility break.

## Validation

Author evidence used a freshly built pinned jq 1.8.1 plus bundled Oniguruma:

- `--run-tests upstream/jq/tests/onig.test`: 47/47 passed;
- `--run-tests upstream/jq/tests/manonig.test`: 19/19 passed;
- focused direct probes covered all flags, errors, ordering, empty and
  multibyte matches, duplicate named captures, embedded NUL, and invalid UTF-8
  normalization;
- exact multibyte zero-width probes produced three complete empty-match records
  for `"é"`, offsets `[0,1,1]`, the same offsets on participating named empty
  captures, and five offsets `[0,1,1,1,1]` for the four-byte subject `"😀"`;
- `"aéz" | match("(?<x>é)")` produced a nonempty whole match and capture at
  codepoint offset 1, length 1, with string `"é"`, preserving the separate
  nonempty-range invariant;
- evidence/schema checks and `make validate` are required before handoff.

Exact-head adversarial diff assessment and fresh source-aware semantic-parity
and regex test-gap/falsification review lanes are required. A later C-binding
implementation additionally requires Odin ownership/resource-safety review.
