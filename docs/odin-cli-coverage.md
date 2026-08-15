# Odin CLI coverage snapshot

This is a coordinator snapshot for the accepted Odin CLI lineage, not a claim
of upstream jq compatibility. The immutable `upstream/jq` tree remains the
behavioral oracle.

## Current measured checkpoint

At integration head `49485252`, the authoritative selected catalog measurement
is **504/522 passed, 18 failed, 0 harness errors**
(`/tmp/coverage-empty-pattern.json`). The bounded same-name destructuring alternation
subset covers jq.test:952, :959, :966, :973, :980, :987, :994, :1001, :1008,
:1015, :1022, and :1029 through existing Binding/Try
continuations; the remaining `?//` forms still require a first-class
alternation ABI. Persistent `input` stream behavior is covered by
`compat/input-stream.jq.test` and decision `docs/decisions/0331-input-stream-implementation.md`.
Undefined-variable compile diagnostics now include jq-compatible source/name spans
and carets (jq.test:560); boolean object-key diagnostics remain deferred.
Invalid string escapes now preserve the lexical message and offending-line caret
(jq.test:63); broader parser diagnostic wording remains deferred.
Constant non-string object keys now report jq-compatible type diagnostics and
inner-key carets (jq.test:127, :139); arithmetic-key parser wording remains deferred.
Single-character unmatched braces now preserve jq's source-located parse
diagnostics (jq.test:2033, :2039); broader parser recovery remains deferred.
Empty destructuring delimiters now preserve jq's token-specific diagnostics
(jq.test:548, :554); multi-diagnostic parser recovery remains deferred.
Root iterator filter updates are covered by
`compat/iterator-rhs-try-tonumber.jq.test` and decision
`docs/decisions/0017-iterator-rhs-continuation.md`; this accounts for the
selected gains at jq.test:1257 and :2348. Sequential top-level definition
metadata is covered by syntax/compiler tests and remains distinct from the
deferred nested lexical-definition contract.
Static `group_by(.field)` keyed materialization is covered by
`compat/group-by-keyed.jq.test` and decision
`docs/decisions/0333-group-by-keyed-materialization.md`; the selected catalog
total is unchanged because jq.test:1639 also contains deferred dynamic and
multi-key grouping forms.
The uppercase `INDEX(stream; key)` case at jq.test:2047 is covered by
`compat/index-generator.jq.test` and decision
`docs/decisions/0349-index-generator-lowering.md`; the source stream is
materialized and keyed entries are passed through the existing `from_entries`
path.
The filtered iterator deletion case at jq.test:1253 is covered by
`compat/filtered-iterator-delete.jq.test` and decision
`docs/decisions/0350-filtered-iterator-delete.md`; only the canonical
`select(...)`-to-`empty` shape enters this lowering.
The recursive `walk(filter)` case at jq.test:2388 is explicitly
covered by `compat/walk-filter-postorder.jq.test` and decision
`docs/decisions/0348-walk-filter-ast-lowering-prototype.md`; it uses recursive
AST calls with post-order `Map`/`Map_Values` rebuilding rather than a driver
rewrite.
Parameterized callable arithmetic is now routed through real argument/callee
frames for the bounded `+`, `-`, `*`, `/`, and `%` body shapes; focused parity
is covered by `compat/parameterized-call-arithmetic.jq.test` (9/9). Unsupported
callable bodies continue through the existing module fallback.
Generated path assignment for bounded literal path streams is covered by
`compat/path-assignment-generated.jq.test` (7/7); dynamic components and
filter-valued `|=` updates remain deferred under decision 0356.
Generated path calls now preserve jq's result-bearing invalid-path diagnostics
for scalar and non-path array results; this is covered by the extended path
assignment shard and decision 0357.
Instruction-valued dynamic index assignment for the bounded root form
`.[{}] = 0` now preserves jq's typed errors and optional suppression; its
focused 10-case shard is `compat/dynamic-index-assignment.jq.test` and the
implementation contract is `docs/decisions/0360-dynamic-index-assignment-implementation.md`.
Binding-derived assignment paths such as jq.test:2088 remain deferred under
`docs/decisions/0358-binding-aware-path-assignment-boundary.md`; value binding
works, but path capture and copy-on-write continuation are not yet unified.
Static deletion from a `null` base now preserves jq's no-op semantics for
`.foo`, `.[0]`, and `.foo[0]`; the focused shard is
`compat/static-del-null.jq.test` and the contract is recorded in
`docs/decisions/0334-static-del-null-base.md`. Typed diagnostics for invalid
non-null deletion targets remain a separate deferred path-update contract.
Root iterator defined-or updates (`.[] //= FILTER`) reuse the resumable
iterator-update contract; the focused shard is
`compat/iterator-defined-or.jq.test` and the decision is
`docs/decisions/0335-static-iterator-defined-or.md`. The selected gain is
the upstream iterator defined-or case at jq.test:1357. Direct diagnostics for
some pre-existing dynamic child errors remain tracked separately from this
slice; caught payloads and update cardinality match jq.
Root static-field filter updates (`.name |= FILTER`) now use a child-bearing
resumable opcode; the focused 10-case shard is
`compat/static-field-filter-update.jq.test` and the contract is recorded in
`docs/decisions/0337-static-field-filter-update.md`. Nested index/path updates
remain deferred under
`docs/decisions/0338-nested-static-index-filter-update-boundary.md`.
Static field compound addition is covered by
`compat/field-compound-add.jq.test`, and comma composition of root iterator
compound updates is covered by `compat/iterator-compound-sequence.jq.test`.
The exact pipe-root optional identity update `.identifier |= .?` is covered by
`compat/static-optional-update.jq.test`.
The bounded two-argument uppercase `JOIN($idx; idx_expr)` form is now lowered
to existing `Map`/`Index`/array instructions and passes jq.test:2051; its
focused shard is `compat/join-index.jq.test` and its contract is recorded in
`docs/decisions/0346-join-index-contract.md`. JOIN/3, JOIN/4, and dynamic
index-object streams remain deferred.
Uppercase `IN({}, [])` comma-literal membership is also lowered through the
existing two-child `In` continuation; `compat/in-uppercase-args.jq.test` and
decision `docs/decisions/0347-uppercase-in-comma-contract.md` cover its scalar,
array, object, and null results. The surrounding dynamic `walk` predicate is
still deferred.
Root iterator
compound updates (`+=`, `-=`, `*=`, `/=`, `%=` with numeric literal RHS) are
covered by `compat/iterator-compound-updates.jq.test` (11/11 focused cases;
decision `docs/decisions/0318-root-iterator-compound-updates.md`). Stable keyed
`sort_by(.field)` support is now
implemented with an explicit keyed-sort opcode and focused-tested in
`compat/sort-by-key-stable.jq.test`; equal keys retain input order while the
ordinary `sort` opcode remains unchanged. It does not add a selected catalog
case yet because the existing selected sort cases are already covered. The
one-case gain over the prior 456/522 checkpoint covers jq-compatible nonfinite JSON input framing at
`upstream/jq/tests/jq.test:1290`; the focused shard is
`compat/cli-nonfinite-framing.jq.test` and the implementation decision is
`docs/decisions/0320-cli-nonfinite-framing.md`. The preceding checkpoint’s
gain covered multi-output static slice assignment at
`upstream/jq/tests/jq.test:478`; the focused shard is
`compat/static-slice-multi-output.jq.test` and the implementation decision is
`docs/decisions/0317-static-slice-multi-output.md`. Root `.[] = scalar`
assignment is also now implemented and focused-tested in
`compat/iterator-assignment.jq.test` (`docs/decisions/0325-root-iterator-assignment.md`),
and the nonfinite framing support above allows its selected catalog case at
`jq.test:1289` to pass. The
root `.[] |= empty` deletion is now also covered by
`compat/iterator-delete.jq.test` (`docs/decisions/0326-root-iterator-empty-update.md`);
its selected upstream cases still combine unsupported update-path forms, so the
catalog total remains unchanged. The preceding three-case
gain covered nested parenthesized `try`/`catch` stream handling in
`upstream/jq/tests/jq.test:2308,2312,2317`; the focused shard is
`compat/nested-try-streams.jq.test` and the implementation decision is
`docs/decisions/0323-nested-try-pipe-state.md`. Immediate binary dynamic index
keys remain covered by `compat/dynamic-index-arithmetic.jq.test` and decision
`docs/decisions/0322-dynamic-index-arithmetic.md`. Parenthesized/filter-valued
index arithmetic remains explicitly deferred.

## Current evidence

- Baseline integration head: `1a98ae1`.
- Static postfix indexing: `2e15478` (`.[N]` and `.field[N]`, literal
  non-negative integer bounds only).
- CLI diagnostic parity for string-key indexing: `f6babcc`; this preserves
  container-specific wording for non-numeric keys while leaving numeric-index
  errors on their bounded path.
- Bounded `atan`: `7a8135a`; its focused shard passes 1/1. The full catalog
  remains at 93/522 because jq’s unrounded floating-point text for the
  standalone `atan` case still differs from the candidate serializer.
- A sin/cos implementation was exercised and reverted (`294d9a6` / `9c9b873`)
  after its nonzero oracle shard exposed the same serializer mismatch
  (`cos(1)`); it remains a queued lane until native-number formatting is fixed.
- ASCII case transforms (`353bb2d`) and array-only `reverse` (`1d68db0`, with
  integration repairs in `43d1d46`) now pass their focused shards. The full
  catalog moved to 94/522 passing filters (428 remaining); the CLI harness
  reports 312 subprocess and 41 differential checks.
- Bounded ASCII `implode` (`932b819`) passes its focused shard and all package
  tests. It does not change the catalog total yet because the remaining core
  `implode` cases require Unicode code-point handling; that limitation is
  recorded in `compat/implode.md`.
- Bounded ASCII `explode` (`866a593`) also passes its focused shard and the
  full package suite. Its Unicode cases remain deferred, so the catalog is
  still 94/522; the implementation is intentionally not represented as full
  jq `explode` compatibility.
- `keys_unsorted` is now integrated at `1755567` with insertion-order object
  and array shards passing. The catalog remains 94/522 because its broader
  upstream cases still include unsupported surrounding filter forms.
- String-only `tostring` (`6ef3c6c`) passes its shard and all package tests;
  numeric, array, and object conversion remains deferred, so the catalog is
  still 94/522.
- Canonical `{key,value}` `from_entries` (`b6ff227`) passes its focused shard,
  package tests, and CLI smoke test. Alternate entry-key spellings and
  malformed/non-array diagnostics remain deferred; catalog coverage is still
  94/522.
- Canonical object `to_entries` (`80fe8a7`) passes its shard and package suite;
  the full catalog moved to 95/522 (427 remaining). Array/non-object forms
  remain deferred.
- Bounded `isnan` (`cb844b0`) passes its finite-number shard and package suite;
  the full catalog remains 95/522 because this parser snapshot cannot yet
  construct jq's `nan` literal, so positive-NaN and non-number diagnostic
  cases remain deferred.
- Bounded `not` (`a33cefa`) passes its truthiness shard and package suite;
  the full catalog is now 96/522 (426 remaining). Its zero-argument truthiness
  form is covered; generator and richer control-flow compositions remain
  deferred.
- Bounded `utf8bytelength` (`51d7b86`) passes its ASCII/UTF-8 shard and package
  suite; the full catalog is now 97/522 (425 remaining). Valid string values
  are covered, while typed non-string diagnostics and malformed UTF-8 remain
  deferred to a follow-up parity lane.
- Bounded zero-output `empty` (`1bf7a1b`) passes its generator/exhaustion shard
  and package suite; the full catalog is now 98/522 (424 remaining). Its
  zero-argument form is covered; argument-bearing and richer control-flow
  combinations remain deferred.
- Bounded `values` (`d3ec1bd`) passes null suppression and scalar passthrough
  shards with the full package suite; the full catalog is now 99/522 (423
  remaining). Object/array stream compositions and richer argument forms are
  still deferred.
- Bounded zero-argument `arrays` (`537b6fc`) passes array selection and scalar
  suppression shards with the full package suite; the full catalog is now
  100/522 (422 remaining). Object/type-predicate families and generator
  compositions remain deferred.
- Bounded zero-argument `objects` (`c076cb8`) passes object selection and
  scalar suppression shards with the full package suite; the full catalog is
  now 101/522 (421 remaining). The remaining type-predicate families and
  generator compositions are still deferred.
- Bounded zero-argument `iterables` (`f20eddb`) passes array/object selection
  and scalar suppression shards with the full package suite; the full catalog
  is now 102/522 (420 remaining). More general generator and predicate
  compositions remain deferred.
- Bounded zero-argument `scalars` (`4c339c6`) passes scalar selection and
  array/object suppression shards with the full package suite; the full
  catalog is now 103/522 (419 remaining), completing the basic type-filter
  family while richer generator forms remain deferred.
- Bounded zero-argument `booleans` (`83269c4`) passes boolean selection and
  non-boolean suppression shards with the full package suite; the full catalog
  is now 104/522 (418 remaining). Other scalar subtype predicates and richer
  generator forms remain deferred.
- Bounded zero-argument `nulls` (`131d300`) passes null selection and
  non-null suppression shards with the full package suite; the full catalog is
  now 105/522 (417 remaining). Remaining scalar subtype and generator forms
  are still deferred.
- Bounded zero-argument `floor` (`176dc20`) passes positive and negative
  numeric rounding shards with the full package suite; the full catalog is now
  107/522 (415 remaining). Non-number/special numeric diagnostics remain
  deferred.
- Bounded zero-argument `round` (`a7ed3ae`) passes positive and negative
  rounding shards and the full package suite. The catalog remains 107/522
  because the selected upstream cases overlap already-covered rounding paths;
  non-number/special numeric diagnostics remain deferred.
- Bounded zero-argument `transpose` (`20859a1`) passes ragged-array null-fill
  and empty-input shards with the full package suite; the full catalog is now
  109/522 (413 remaining). Non-array diagnostics remain deferred.
- Bounded zero-argument `unique` (`795e408`) now performs ownership-safe
  sorting and deduplication, including duplicate preservation regression cases;
  its shard and package suite pass, and the full catalog is now 111/522 (411
  remaining).
- Bounded zero-argument `sort` (`b999fac`) performs owned insertion sorting
  with jq-compatible mixed-value ordering and duplicate retention. Its focused
  shard and package suite pass; the full catalog is now 112/522 (410
  remaining).
- Bounded zero-argument `ceil` (`c4944f7`) passes its numeric oracle shard and
  the full package/CLI suites. The full catalog remains 112/522 because its
  selected catalog case overlaps an already-covered numeric path; non-number
  diagnostics remain deferred.
- Bounded zero-argument `flatten` (`1af2c9b`) recursively flattens nested
  arrays with ownership-safe output construction. Its focused shard and full
  package/CLI suites pass; the full catalog is now 113/522 (409 remaining).
- Bounded zero-argument `nan` and positive `infinite` (`5d64e4a`) pass their
  focused 3/3 oracle shard and package checks. The full catalog is now 114/522
  (408 remaining); unary `-infinite` remains a separate Negate contract gap.
- Bounded zero-argument `any`/`all` (`f620eb8`) pass five array truthiness and
  empty-identity oracle cases. The full catalog is now 119/522 (403 remaining);
  generator and condition overloads remain deferred.
- Bounded zero-argument `isfinite` (`5532f38`) passes its numeric finite/NaN/
  infinity predicate shard and package suite. The full catalog remains 119/522
  because the selected case overlaps existing numeric coverage.
- Bounded literal-separator `join` (`c5dbcd9`) passes its 3/3 oracle shard and
  package suite. The full catalog is now 122/522 (400 remaining); dynamic
  separators and jq's number/boolean member coercions remain deferred.
- Package validation and the full Odin package test suite pass on the
  integration worktree. The CLI harness reports 316 subprocess checks and 41
  differential checks.
- The bounded `isnormal` numeric predicate (`73cbdf4`) passes its 5/5 oracle
  shard and the full Odin package suite. It does not add a new jq catalog case
  on this snapshot; subnormal, NaN, infinity, zero, and non-number behavior is
  covered by the focused shard and documented in decision `0095`.
- The bounded literal `contains("...")` predicate (`36b9268`, with the
  integration fixture correction in `ff89ff8`) passes its 4/4 oracle shard,
  the full package suite, and the CLI harness. The full pinned catalog now
  measures **128/522 passed and 394 failed**. The six newly passing cases are
  the string-substring cases at `upstream/jq/tests/jq.test:1404-1425`;
  recursive array/object containment and dynamic arguments remain deferred.
- The follow-up guard (`106c0be`) turns unsupported array/object literal
  arguments into controlled parse errors instead of parser assertions; the
  accepted string-literal behavior and the 128/522 catalog result are
  unchanged.
- Bounded literal-separator `split` (`e7c22aa`, including the empty-input fix)
  passes four jq oracle cases at `upstream/jq/tests/jq.test:1495,1575,1579`
  plus the empty-input regression; the empty-separator Unicode case at line
  1499 remains explicitly skipped. The exact full catalog remains
  **131/522 passed and 391 failed** because the added regression exercises an
  already-selected semantic path.
- Bounded literal ASCII `index`/`rindex`/`indices` (`ebf5160`) passes its
  3/3 oracle shard and adds three catalog cases at
  `upstream/jq/tests/jq.test:1515-1521,1555-1557`. The exact catalog now
  measures **134/522 passed and 388 failed**. Unicode, empty-needle,
  array-needle, dynamic, and two-argument forms remain deferred.
- The exact catalog measurement was produced with
  `tools/compat/jq_compat.py` against jq 1.8.1 (oracle SHA
  `30df4803a4ebbfd2741b2477d06488ce5973e3517cb1121d56be4b1fad9efa8d`) and
  summarized with `tools/compat/catalog_report.py` at integration head
  `ebf5160`.
- The jq catalog moved from 90/522 passing filters at the baseline to 93/522
  after static indexing; 429 catalog cases still fail. The catalog report is
  generated with `tools/compat/catalog_report.py` and is intentionally kept as
  an external artifact rather than committed output.
- The focused postfix-index shard passes 5/5 against the pinned jq oracle;
  see `compat/postfix-index.md` and decision `0066`.
- The index-family follow-up (`91add64`) now reports UTF-8 search positions as
  jq-compatible code-point offsets and covers null/array inputs. Its focused
  shard passes 10/10, the independent ownership/parity review found no issues,
  and the exact catalog is now **137/522 passed and 385 failed**.
- Literal `startswith`/`endswith` (`b342e11`) adds two string-prefix/suffix
  cases from `upstream/jq/tests/jq.test:1487-1491`. Its focused shard and full
  Odin package/CLI suites pass; the exact catalog is now **139/522 passed and
  383 failed**. Dynamic arguments and non-string diagnostics remain deferred.
- Literal `flatten(depth)` (`aee2c3a`, with the negative-depth guard `3101ffd`)
  adds three depth-controlled cases from `upstream/jq/tests/jq.test:1761-1773`.
  Its focused shard and full Odin package/CLI suites pass; the exact catalog is
  now **142/522 passed and 380 failed**. Dynamic depth and full jq diagnostics
  remain deferred.
- Unicode White_Space handling for `trim`, `ltrim`, and `rtrim` (`d5305b7`)
  adds a focused 2/2 shard covering non-ASCII whitespace and preserves the
  existing ASCII behavior. The exact catalog is now **143/522 passed and 379
  failed**.
- Corrected native-number formatting (`f8db275`) fixes jq's short scientific
  spelling for tiny finite values while preserving ordinary/large-number
  thresholds and overflow behavior. Its focused shard passes 1/1 and the exact
  catalog is now **144/522 passed and 378 failed**.
- Literal `join(",")` scalar-member coercion (`305366b`) now matches jq for
  strings, nulls, booleans, and numeric/scientific literals. Its focused shard
  passes 3/3 and the exact catalog is now **145/522 passed and 377 failed**;
  arrays/objects, dynamic separators, and native arithmetic-number formatting
  remain deferred.
- Unicode `implode`/`explode` (`a52494c`, decision `0101`) now encodes and
  decodes Unicode code points, truncates positive fractional code points, and
  applies jq's replacement-character/NaN behavior. Its focused shards pass
  2/2 for `implode` and 1/1 for `explode`; package, full unit, build, and CLI
  checks pass. The exact catalog is now **146/522 passed and 376 failed**;
  malformed UTF-8 and broader diagnostic wording remain deferred.
- Literal `has(...)` (`67ce493`, decisions `0102-0104`) now covers object-key
  and array-index presence, fractional-index truncation, null-input false
  results, and the `has(nan)` false case. Its focused oracle shard passes 8/8;
  package/unit/build and CLI checks pass, and the exact catalog is now
  **147/522 passed and 375 failed**. Negative-index parsing, dynamic
  arguments, and `map(has(...))` remain deferred.
- Numeric literal `bsearch(...)` (`487eea9`, decision `0105`) now emits jq's
  exact-match or negative insertion-position encoding for sorted numeric arrays.
  Its focused oracle shard passes 3/3 and package/build checks pass; the full
  catalog remains **147/522 passed and 375 failed** because its selected cases
  currently exercise deferred multi-needle/object forms. Dynamic needles,
  object ordering, and non-array diagnostics remain deferred.
- Simple object-literal `bsearch(...)` needles (`d2b0ffb`, decisions `0106`
  and the duplicate tie fixes) now reuse the existing recursive ordering
  comparator with owned reconstructed object values and jq's upper-midpoint
  duplicate behavior. Its focused shard passes 10/10 and the exact catalog is
  **148/522 passed and 374 failed**. Multi-needle, nested-object, dynamic, and
  non-array forms remain deferred.
- Empty-separator `split("")` (`3113d56`, decision `0107`) now splits UTF-8
  strings by Unicode code point and returns an empty array for empty input,
  while preserving non-empty separator behavior. Its focused shard passes 6/6
  and the exact catalog is now **149/522 passed and 373 failed**. Non-string
  diagnostics and dynamic separators remain deferred.
- Literal unary negative numbers (`972a775`, decisions `0108` and the
  negative-zero correction) now lower as owned negative numeric literals,
  covering scalar, array, arithmetic, range, and jq-specific negative-zero
  spelling cases. Its focused shard passes 3/3 and the exact catalog is now
  **152/522 passed and 370 failed**. Dynamic `-.`, richer unary forms, and
  negative arguments to deferred parameterized builtins remain deferred.
- Literal `ltrimstr`, `rtrimstr`, and `trimstr` (`6049280`, decision `0109`)
  now cover prefix removal, suffix removal, composition, and jq's empty-string
  behavior. The focused shard passes 6/6 and the exact catalog is now
  **155/522 passed and 367 failed**. Dynamic arguments, non-string diagnostics,
  and full Unicode edge behavior remain deferred.
- Bounded `tonumber` (`99dd95c`, decision `0110`) now handles numeric identity
  and literal numeric-string conversion. Its focused shard passes 3/3 and the
  exact catalog is now **156/522 passed and 366 failed**. Invalid strings,
  dynamic inputs, precision edges, and full diagnostic wording remain deferred.
- Zero-argument array `min`/`max` (`567d8fc`, decision `0111`) now reduce using
  jq's existing total value ordering and return `null` for empty arrays. Its
  focused shard passes 2/2 and package/build checks pass; the catalog remains
  **156/522 passed and 366 failed** because the upstream min/max fixtures are
  grouped with unsupported `min_by`/`max_by`. Non-array diagnostics and those
  parameterized reducers remain deferred.
- `from_entries` aliases and missing values (`930145e`, decisions `0112` and
  the follow-up fix) now accept jq's lowercase/capitalized `key`/`Key`/`name`/
  `Name` plus `value`/`Value` spellings, defaulting an omitted value to `null`.
  Its focused shard passes 2/2 and the exact catalog is **157/522 passed and
  365 failed**. Malformed entries and non-array diagnostics remain deferred.
- Literal numeric and non-empty array needles for `index`/`rindex`/`indices`
  (`a4db92a`, decision `0113`) now support scalar matching and contiguous-array
  searches while preserving the string needle shard. The new shard passes 3/3,
  the existing shard passes 10/10, and the exact catalog is now **160/522
  passed and 362 failed**. Empty-array needles, dynamic/two-argument forms,
  Unicode edges, and detailed diagnostics remain deferred.
- Bounded `toboolean` (`aa2408d`, decision `0114`) now preserves boolean inputs
  and converts the exact string literals `"true"` and `"false"`. Its focused
  shard passes 4/4; package tests and the CLI harness pass (316 subprocess and
  41 differential checks). The full catalog remains **160/522 passed and 362
  failed** because its selected `toboolean` cases are embedded in unsupported
  `map`/`try` compositions. Invalid strings, non-string diagnostics, and
  dynamic/generator forms remain deferred.
- Empty string needles for the existing `index`/`rindex`/`indices` family
  (`03f955f`, decision `0115`) now match jq's empty-needle behavior: string
  inputs return `null`, `null`, and `[]`, while null input propagates null.
  The new shard passes 3/3 and the prior index-family shard remains 10/10;
  the exact catalog is now **161/522 passed and 361 failed**. Empty-array
  needles, dynamic/two-argument forms, and detailed diagnostics remain
  deferred.
- Static object-literal `contains` (`162c906`, fixes `415eac0` and `08402f0`,
  decision `0116`) now supports recursive object and array subset matching.
  Nested object/array kind mismatches return `false`, while top-level
  container mismatches retain jq's runtime-error class. The focused shard
  passes 7/7 and the string-literal shard remains 4/4; the fresh full catalog
  is **164/522 passed and 358 failed**. Dynamic arguments, broader array
  literal syntax, and detailed diagnostic wording remain deferred.
- Quoted field postfixes (`98f50b5`, decision `0117`) now support non-interpolated
  `."foo"` and chained forms such as `."foo"."bar"` and `.foo."bar"` by
  reusing the existing Field representation. The focused shard passes 3/3,
  package/build checks pass, and the full catalog is **165/522 passed and 357
  failed**. Interpolated/dynamic fields and assignment/update forms remain
  deferred.
- String-key bracket postfixes (`c2d4624`, decision `0118`) now support literal
  accesses such as `.["foo"].bar` and chained `.["foo"]["bar"]`, including
  missing-key null results. The focused shard passes 3/3, package/build checks
  pass, and the full catalog is **166/522 passed and 356 failed**. Dynamic or
  interpolated keys and assignment/update forms remain deferred.
- `@base64`/`@base64d` (`f35a12f`, fixes `310cdad` and `6d3a703`, decision
  `0119`) now encode scalar-coerced values, decode valid padded/unpadded input,
  reject malformed string payloads, and preserve jq's replacement-byte results
  for scalar non-string inputs. The focused shard passes 8/8; package/build
  checks pass and the full catalog is **168/522 passed and 354 failed**. Other
  format filters, array/object coercion, and exact diagnostic wording remain
  deferred.
- `@uri`/`@urid` (`e998b35`, fix `6629496`, decision `0120`) now provide
  RFC3986-style scalar encoding/decoding, including percent-encoded UTF-8 and
  jq-compatible replacement behavior for raw non-ASCII decode input. The
  focused shard passes 5/5, package/build checks pass, and the full catalog is
  **170/522 passed and 352 failed**. Other format filters and detailed
  malformed-input diagnostics remain deferred.
- Scalar `@html` (`17e138f`, decision `0121`) now performs jq-compatible HTML
  escaping for `&`, `<`, `>`, apostrophe, and quote while coercing scalar input
  to text and preserving UTF-8. Its focused shard passes 3/3 and package/build
  checks pass; the catalog remains **170/522 passed and 352 failed** because
  jq's format-argument/interpolation form is deferred. Container coercion and
  malformed UTF-8 diagnostics remain deferred.
- `@text` (`bf713fb`, container fix `eee3756`, decision `0122`) now coerces
  scalars and compact-JSON stringifies arrays/objects, including nested values,
  while preserving raw strings and UTF-8. The focused shard passes 5/5,
  package/build checks pass, and the catalog remains **170/522 passed and 352
  failed** because format-argument/interpolation cases are deferred.
- Zero-argument `@json` (`a832f20`, decision `0123`) now reuses the reviewed
  compact JSON serializer for scalar, string, array, object, null, boolean, and
  nested values. Its focused shard passes 4/4 and package/build checks pass;
  the catalog remains **170/522 passed and 352 failed** because format
  arguments and sibling format filters remain deferred.
- JSON exponent formatting fix (`4a1b3fd`) now emits jq-compatible uppercase
  `E` notation with explicit positive signs (`1e20` → `1E+20`, `1e-7` →
  `1E-7`). The expanded JSON shard passes 5/5 and numeric serializer
  regressions remain green.
- Scalar-array `@csv` (`47d5a19`, decision `0124`) now implements RFC4180
  quoting, doubled quotes, null-as-empty fields, booleans, UTF-8, and jq-style
  exponent formatting. Its focused shard passes 3/3 and package/build checks
  pass; the catalog remains **170/522 passed and 352 failed** because the
  selected upstream format cases are grouped with deferred sibling formats and
  interpolation forms. Nested containers and exact diagnostic wording remain
  deferred.
- Scalar-array `@tsv` (`6db69f9`, decision `0125`) now escapes backslashes,
  tabs, newlines, and carriage returns while coercing null, booleans, numbers,
  exponents, and UTF-8 fields. Its focused shard passes 3/3 and package/build
  checks pass; the catalog remains **170/522 passed and 352 failed** because
  format arguments, sibling formats, and nested containers remain deferred.
- Scalar-array `@sh` (`2666e13`, decision `0126`) now emits POSIX
  single-quoted fields with jq-compatible apostrophe escaping, scalar
  coercion, UTF-8, exponents, and empty-array behavior. Its focused shard
  passes 3/3 and package/build checks pass; the catalog remains **170/522
  passed and 352 failed** because format arguments, sibling formats, and
  nested containers remain deferred.
- Scalar-input `@sh` correction (`a7f39ca`) now emits one quoted field instead
  of requiring an array, matching jq for scalar, null, and string inputs while
  preserving array behavior. The expanded shard passes 5/5 and the full
  catalog is now **171/522 passed and 351 failed**.
- Zero-argument `tojson` (`111c5db`, decision `0127`) now serializes scalar,
  string, null, boolean, exponent, and nested array/object values using the
  reviewed compact JSON serializer. Its focused shard passes 4/4 and
  package/build checks pass; the catalog remains **171/522 passed and 351
  failed** because `fromjson` and complex expression forms remain deferred.
- Scalar `fromjson` (`4454e16`, whitespace fix `0271d9c`, decision `0128`) now
  parses null, booleans, integers, floats, and surrounding JSON whitespace.
  The focused shard passes 7/7 and package/build checks pass; the full catalog
  is now **172/522 passed and 350 failed**. Arrays, objects, escaped strings,
  and detailed malformed-input diagnostics remain deferred pending the JSON
  package-boundary decision.
- `abs` container passthrough (`0eda02a`, decision `0129`) now clones arrays
  and objects unchanged, matching jq while retaining numeric absolute values,
  string identity, and existing error classes. Its focused shard passes 4/4;
  package/build checks pass and the catalog remains **172/522 passed and 350
  failed** because the grouped upstream gap adds no independent selected case.
- Numeric `length` semantics (`53589b1`, decision `0130`) now return the
  absolute value for positive, negative, fractional, and zero numbers while
  preserving string/array/object/null behavior. Its focused shard passes 5/5;
  package/build checks pass and the catalog remains **172/522 passed and 350
  failed** because selected numeric-length cases are grouped with unsupported
  expressions.
- `isnan` type semantics (`de82c48`, decision `0131`) now return `false` for
  null, booleans, strings, arrays, and objects while preserving numeric
  classification. Its focused shard passes 7/7 and package/build checks pass;
  the catalog remains **172/522 passed and 350 failed** because these cases are
  grouped outside the parser-supported catalog subset.
- Object `add` semantics (`4101b65`, decision `0132`) now reduce object values
  in insertion order and return `null` for empty objects, while preserving
  array concatenation and existing error classes. Its focused shard passes
  5/5 and package/build checks pass; the catalog remains **172/522 passed and
  350 failed** because the selected object cases are grouped with unsupported
  expressions.
- Empty-value `reverse` semantics (`c227a07`, decision `0133`) now return an
  empty array for null, zero, empty strings, and empty objects, while retaining
  array reversal and errors for non-empty unsupported scalar/object inputs. Its
  focused shard passes 5/5 and package/build checks pass; the catalog remains
  **172/522 passed and 350 failed** because these cases are grouped with
  unsupported expressions.
- All-value `tostring` semantics (`883327e`, decision `0134`) now preserve
  strings and JSON-stringify null, booleans, numbers, arrays, and objects using
  the owned text serializer. Its focused shard passes 6/6 and package/build
  checks pass; the catalog remains **172/522 passed and 350 failed** because
  the selected tostring cases are grouped with unsupported expressions.
- The `numbers` type filter (`c88daf4`, decision `0135`) now emits number inputs
  unchanged and suppresses all other JSON kinds, reusing the selector path.
  Its focused shard passes 5/5 and package/build checks pass; the catalog
  remains **172/522 passed and 350 failed** because the builtin has no
  standalone selected jq.test case.
- The `strings` type filter (`236e0d4`, decision `0136`) now emits string inputs
  unchanged and suppresses all other JSON kinds, mirroring the numbers filter.
  Its focused shard passes 5/5 and package/build checks pass; the catalog
  remains **172/522 passed and 350 failed** because the builtin has no
  standalone selected jq.test case.
- The `finites` type filter (`968f102`, corrected by `fa2a01c`, decision `0137`)
  now emits numeric inputs except infinities (jq 1.8 treats NaN as finite) and
  suppresses non-number values, reusing the finite-number predicate. Its
  focused shard passes 7/7 against the pinned oracle and package/build checks
  pass; the catalog remains **172/522 passed and 350 failed** because the
  builtin has no standalone selected jq.test case. The local jq 1.7 oracle
  lacks this jq 1.8 builtin; special-value coverage is pinned-oracle
  dependent.
- The `normals` type filter (`a1b7f94`, decision `0138`) now emits finite,
  non-zero numbers at or above the binary64 normal threshold and suppresses
  zero, subnormal, NaN, infinity, and non-number values. Its focused shard
  passes 7/7 against the pinned oracle and package/build checks pass; the
  catalog remains **172/522 passed and 350 failed** because the builtin has no
  standalone selected jq.test case.
- The zero-argument `log` builtin (`c964b84`, corrected by `92c8887`, narrowed
  by `0147`, decisions `0139`/`0140`/`0147`) now computes the natural logarithm
  for numeric inputs. Its focused shard passes 4/4 against the pinned oracle
  and package/build checks pass; the catalog remains **172/522 passed and 350
  failed** because selected log cases are grouped with unsupported expressions.
  Generator/non-number diagnostics and some native-libm final-digit cases are
  deferred.
- The zero-argument `last` builtin (`e3b8a56`, decision `0141`) now returns the
  final element of arrays and `null` for empty arrays or null input, while
  deferring generator forms and broader wrong-type diagnostics. Its focused
  shard passes 3/3 against the pinned oracle and package/build checks pass; the
  catalog remains **172/522 passed and 350 failed** because selected `last`
  cases are generator expressions.
- The zero-argument `isinfinite` predicate (`9f02282`, decision `0143`) now
  returns true only for infinite numeric inputs and false for finite, NaN, and
  non-number values. Its focused shard passes 3/3 against the pinned oracle;
  the full package suite also passes. The catalog remains **172/522 passed and
  350 failed** because the selected predicate cases are grouped with broader
  unsupported expressions.
- The zero-argument `first` builtin (`1e3b491`, corrected by `8edfc71`, decision
  `0142`) now returns the first element of arrays and `null` for empty arrays or
  null input, while deferring generator forms and broader wrong-type
  diagnostics. Its focused shard passes 3/3 against the pinned oracle, and the
  full package suite passes after the compiler-shape fixture correction. The
  catalog remains **172/522 passed and 350 failed** because selected `first`
  cases are generator expressions.
- The zero-argument `log10` builtin (`cc4148a4`, corrected by `0a35271f`,
  decision `0144`) now computes base-10 logarithms for numeric inputs. Its
  focused shard passes 2/2 against the pinned oracle, and the full package
  suite passes after the compiler-shape fixture correction. The catalog remains
  **172/522 passed and 350 failed** because selected log10 cases are grouped
  with unsupported expressions; `log10(0.1)` retains a documented native-libm
  final-digit precision caveat.
- The zero-argument `log2` builtin (`7253b0f6`, corrected by `f517f296`,
  decision `0145`) now computes base-2 logarithms for numeric inputs. Its
  focused shard passes 2/2 against the pinned oracle, and the full package
  suite passes after the compiler-shape fixture correction. The catalog remains
  **172/522 passed and 350 failed** because selected log2 cases are grouped
  with unsupported expressions; `log2(10)` retains a documented one-ULP
  native-libm precision caveat.
- The zero-argument `exp` builtin (`c4ef287e`, decision `0146`) now computes
  the exponential for numeric inputs. Its focused shard passes 4/4 against the
  pinned oracle and the full package suite passes. The authoritative catalog
  remains **172/522 passed and 350 failed** after narrowing the native-number
  formatter to avoid regressions in existing numeric-boundary cases; overflow,
  non-number diagnostics, and platform-sensitive final digits remain deferred.
- The zero-argument `exp2` builtin (`5d2392c4`, decision `0148`) now computes
  two-to-the-power-of-n for numeric inputs. Its focused shard passes 4/4
  against the pinned oracle, package/build checks and full tests pass, and the
  full catalog remains **172/522 passed and 350 failed** because selected exp2
  cases are embedded in unsupported compositions. Non-number diagnostics,
  overflow/underflow, and platform-sensitive fractional values remain deferred.
- The zero-argument `exp10` builtin (`01e3a4c2`, decision `0149`) now computes
  ten-to-the-power-of-n for numeric inputs. Its focused shard passes 4/4 against
  the pinned oracle, package/build checks and full tests pass, and the catalog
  remains **172/522 passed and 350 failed** because selected exp10 cases are
  embedded in unsupported compositions. Non-number diagnostics,
  overflow/underflow, and platform-sensitive fractional values remain deferred.
- The zero-argument `asin` builtin (`3f63e385`, decision `0150`) now computes
  inverse sine for numeric inputs using Odin's math implementation. Its
  focused shard passes 3/3 against the pinned oracle, package/build checks and
  full tests pass, and the catalog remains **172/522 passed and 350 failed**.
  Non-number diagnostics and a one-ULP native-libm difference at `asin(0.5)`
  remain deferred;
  cbrt was not added because the pinned Odin API has no cbrt function.
- The zero-argument `acos` builtin (`f9163991`, decision `0151`) now computes
  inverse cosine for numeric inputs using Odin's math implementation. Its
  focused shard passes 3/3 against the pinned oracle, package/build checks and
  full tests pass, and the catalog remains **172/522 passed and 350 failed**.
  Non-number diagnostics and a one-ULP native-libm difference at `acos(0.5)`
  remain deferred.
- The zero-argument `cos` builtin (`1b2214cb`, decision `0152`) now computes
  cosine for numeric inputs using Odin's math implementation. Its focused
  shard passes 3/3 against the pinned oracle, package/build checks and full
  tests pass, and the catalog remains **172/522 passed and 350 failed**.
  Non-number diagnostics and one-ULP native-libm differences at `cos(1)` and
  `cos(0.5)` remain deferred.
- The zero-argument `sin` builtin (`102a9852`, decision `0153`) now computes
  sine for numeric inputs using Odin's math implementation. Its focused shard
  passes 3/3 against the pinned oracle, package/build checks and full tests
  pass, and the catalog remains **172/522 passed and 350 failed**. Non-number
  diagnostics and platform-sensitive interior-value precision remain deferred.
- The zero-argument `tan` builtin (`ddbc199e`, decision `0154`) now computes
  tangent for numeric inputs using Odin's math implementation. Its focused
  shard passes 3/3 against the pinned oracle, package/build checks and full
  tests pass, and the catalog remains **172/522 passed and 350 failed**.
  Non-number diagnostics and one-ULP native-libm differences at interior
  values remain deferred.
- The zero-argument `sinh` builtin (`e55758c7`, decision `0155`) now computes
  hyperbolic sine for numeric inputs using Odin's math implementation. Its
  focused shard passes 3/3 against the pinned oracle, package/build checks and
  full tests pass, and the catalog remains **172/522 passed and 350 failed**.
  Non-number diagnostics, dynamic forms, near-overflow behavior, and
  platform-sensitive precision remain deferred.
- Static `error("literal")` and literal `try error(...) catch ...` forms
  (`eb3e6f5f`, `c82bf039`, decision `0156`) now preserve the owned runtime
  message through evaluator replay and driver formatting. The focused shard
  passes 3/3 against the pinned oracle, package/build checks and full tests
  pass. Dynamic/non-string error arguments, broader `try` forms, `halt`, and
  `debug` remain deferred; the catalog baseline is unchanged at **172/522
  passed and 350 failed**.
- Literal-child `isempty` (`1aea36bf`, decision `0157`) now distinguishes
  `empty` (true) from scalar and null literals (false). Its focused shard
  passes 3/3 against the pinned oracle, package/build checks and full tests
  pass. Array/dynamic/generator children remain deferred; the catalog remains
  **172/522 passed and 350 failed**.
- Literal numeric `range` streams (`8d4af304`, decision `0158`) now support
  one-, two-, and three-argument positive/non-negative forms with jq's
  half-open stream cardinality. Its focused shard passes 4/4 against the
  pinned oracle, package/build checks and full tests pass. The resumed field
  iterator guard was corrected in decision `0159`; the full catalog is now
  **175/522 passed and 347 failed**. Negative-step, dynamic/comma arguments,
  `foreach`, `limit`, and `range(.)` remain deferred in that initial scope.
- Unary-negative and zero-step literal `range` operands (`b24d9a76`, decision
  `0160`) now cover descending half-open streams and empty zero-step/direction
  cases. The focused shard passes 7/7, package/build checks and full tests
  pass, and the full catalog is now **177/522 passed and 345 failed**.
- Identity-child `range(.)` (`ec3c1a0a`, decision `0161`) now supports numeric
  input streams and preserves all outputs through literal `try`/`catch`, with
  graceful caught errors for nonnumeric input. Its focused shard passes 10/10
  against the pinned oracle; package/build checks and full tests pass. The
  catalog remains **177/522 passed and 345 failed** because the selected
  identity cases are grouped with broader unsupported range consumers.
- Bounded UTC `strftime` formatting for parsed datetime arrays (`f446795e`,
  corrected by `edce216b`, decision `0162`) now matches the selected
  `%Y-%m-%dT%H:%M:%SZ` cases, including omitted trailing time fields. Its
  focused shard passes 2/2, package/build checks and full tests pass, and the
  authoritative catalog is **179/522 passed and 343 failed**. Numeric
  timestamps, other format directives, local-time variants, and very short
  arrays such as `[0]` remain deferred.
- Arithmetic-produced positive number text (`edce216b` follow-up, decision
  `0163`) now strips internal leading `+` signs from `tostring`/JSON text.
  The focused shard passes 2/2, package/build checks pass, and the
  authoritative catalog is **180/522 passed and 342 failed**. Input JSON
  spelling and unary-negative canonicalization are unchanged.
- Structured `fromjson` values (`decision 0164`) now delegate to the existing
  JSON parser, covering arrays, objects, strings, and nested round trips. The
  focused shard passes 3/3, package/build checks and full tests pass, and the
  authoritative catalog is **181/522 passed and 341 failed**. Exact parse-error
  wording and dynamic arguments remain deferred.
- Pipe/binding precedence (`decision 0165`) now attaches `as $name` to the
  right-hand pipe filter, preserving the piped input and nested Cartesian
  streams. The focused shard passes 1/1, package/build checks and full tests
  pass, and the authoritative catalog is **182/522 passed and 340 failed**.
  Destructuring and dynamic assignment bindings remain deferred.
- The bounded generator-valued `reduce .[] / .[]` path (`decision 0166`)
  now evaluates the Cartesian division stream before applying its numeric
  update. Its focused shard passes 1/1, package/build checks and full tests
  pass, and the authoritative catalog is **183/522 passed and 339 failed**.
  General generator-valued reducers and `foreach` remain deferred.
- `try`/`catch` binary precedence (`decision 0167`) now leaves surrounding
  operators outside an unparenthesized catch filter, matching jq's additive
  and multiplicative cases. Its focused shard passes 3/3, package/build checks
  and full tests pass, and the authoritative catalog is **184/522 passed and
  338 failed**.
- `try`/`catch` pipe precedence (`decision 0168`) now keeps a following pipe
  outside a comma-separated catch stream, matching jq's two-output case. Its
  focused shard passes 1/1, package/build checks and full tests pass, and the
  authoritative catalog is **185/522 passed and 337 failed**.
- Fixed builtin runtime keys (`decision 0169`) now preserve jq's diagnostic
  messages for invalid `strftime` inputs and non-string trim-family inputs
  through `try ... catch .`. Its focused shard passes 2/2, package/build
  checks and full tests pass, and the authoritative catalog is **186/522
  passed and 336 failed**.
- Catch/comma precedence (`decision 0170`) now leaves a same-level comma in the
  surrounding query stream while retaining binary and pipe binding inside the
  catch branch. Its focused shard passes 2/2, package/build checks and full
  tests pass, and the authoritative catalog is **187/522 passed and 335
  failed**.
- `toboolean` runtime keys (`decision 0171`) now preserve jq's kind/value
  diagnostics through catches for invalid scalar and container inputs. Its
  focused shard passes 3/3, package/build checks and full tests pass, and the
  authoritative catalog is **188/522 passed and 334 failed**.
- `utf8bytelength` runtime keys (`decision 0172`) now preserve jq's kind/value
  diagnostics through catches for invalid non-string inputs. Its combined
  runtime-key shard passes 4/4, and the authoritative catalog is **189/522
  passed and 333 failed**.
- `bsearch` runtime keys (`decision 0173`) now preserve the non-array input
  diagnostic through catches. The combined runtime-key shard passes 5/5, and
  the authoritative catalog is **190/522 passed and 332 failed**.
- Zero-divisor runtime keys (`decision 0174`) now preserve numeric division and
  remainder diagnostics through catches. The combined runtime-key shard
  passes 6/6, and the authoritative catalog is **195/522 passed and 327
  failed**.
- String multiplication (`decision 0175`) now supports bounded string×number
  and number×string repetition, including truncation, null/empty behavior,
  and overflow diagnostics. Its focused shard passes 3/3, and the
  authoritative catalog is **199/522 passed and 323 failed**.
- Unary NaN lowering (`decision 0176`) now allows `-nan` to reuse the existing
  NaN opcode, covering its observable arithmetic behavior. The combined string
  arithmetic shard passes 4/4, and the authoritative catalog is **200/522
  passed and 322 failed**.
- Iterator error catch values (`decision 0212`) now retain jq's typed
  `Cannot iterate over <kind> (<value>)` message through `try .[] catch .`.
  The focused shard passes 2/2, package checks and full tests pass, and a fresh
  catalog run measures **281/522 passed and 241 failed**.
- Lowercase NaN JSON-input framing (`decision 0232`) distinguishes `nan` from
  the shared `null` prefix without changing the owning JSON parser or
  evaluator contracts. The focused shard passes 4/4 and the CLI split-input
  checks pass. Catalog cases at `upstream/jq/tests/jq.test:2277` and `:2365`
  move to pass, for an exact baseline measurement of **299/522 passed and 223
  failed**.
- Zero-catch `try EXP` (`c8edb141`, decision `0250`) now materializes jq's
  implicit `empty` catch branch for static error suppression. Its focused
  shard passes 2/2, package and full unit suites pass, and the current
  authoritative catalog measures **320/522 passed and 202 failed**. Comma
  composition inside zero-catch try, defined-or, and dynamic catches remain
  deferred.
- Boolean `and`/`or` (`6339c2ac`, decision `0252`) now use append-only binary
  opcodes with jq truthiness and short-circuit independently for each output
  of a left-hand stream. The focused shard passes 7/7, package and full unit
  suites pass, and the authoritative catalog measures **322/522 passed and
  200 failed**. Dynamic continuation forms outside the existing binary frame
  remain deferred.
- Unary-negative one-argument `range(-2)` (decision `0253`) now parses and
  reuses the existing empty-interval evaluator. Its focused shard passes 1/1,
  and package/full unit tests remain green. Dynamic range bounds and
  generator-valued operands still require a continuation-frame contract.
- Dynamic arithmetic `range` bounds (decision `0254`) now evaluate bounded
  identity/literal/unary/arithmetic expressions against the current input,
  including `map(range(.; .+2))`. The focused shard passes 6/6 and package/full
  unit tests remain green; the catalog remains **322/522** because these cases
  are embedded in larger unsupported expressions. Generator-valued bounds and
  zero-divisor diagnostic propagation remain deferred.
- Parenthesized static object assignment (decision `0255`) now reuses the
  existing scalar assignment evaluator inside `try (...) catch .`; the focused
  shard passes 2/2 and package, full-unit, and repository validation remain
  green. Nested paths and dynamic assignment remain deferred.
- Zero-catch `try` comma boundaries (decision `0256`) now stop implicit
  `try EXP` before surrounding comma streams; the focused shard passes 3/3 and
  package/full validation remain green. Dynamic catches remain deferred.
- Zero-argument `recurse` (decision `0257`) now recognizes jq's named
  recursive-descent builtin and reuses the existing explicit preorder frame;
  its focused shard passes 3/3. Parameterized `recurse(f)` remains deferred.

## Current authoritative measurement (2026-08-13)

- Integration head `ea386b46` includes the reviewed CLI lineage, the
  `asinh`/`atanh` unary math builtins, filter-parameter validation, the
  static `path`/`paths`/literal `getpath` slice, literal `setpath`, and
  bounded literal `delpaths`, bounded dynamic path iteration, and static path
  forks, and whitespace-tolerant literal postfix module parameters, plus numeric `%Y`, `%m`, and `%d` strftime directives.
  A pinned jq 1.8.1 catalog run selects all **522** upstream cases and passes
  **351**, with **171**
  failing and no harness errors. Package tests, `make validate`, and the CLI
  harness (333 subprocess / 43 differential checks) pass.
- The basic strftime shard passes 4/4. Filter-parameter, computed-key,
  dynamic-path-materialized-result and module-directory-resolution,
  numeric cos/sin parity, lexical-definition snapshots,
  nested-path-map-select, nested-setpath-error, dynamic-path-identity,
  predicate-path, piped-wildcard-path, multi-seed-foreach, Cartesian-foreach,
  index-assignment-error, path-mutation-error, try-defined-or, and nested
  defined-or shards pass 3/3, 2/2, 2/2, 2/2, 2/2, 1/1, 5/5, 2/2, 4/4,
  and 1/1 respectively. The static path focused shard passes 3/3, the dynamic path shard passes 3/3,
  the static path-fork shard passes 2/2. The driver differential harness
  remains green at 333 subprocess and 43 differential checks; the module
  postfix whitespace case is outside the 522-case upstream catalog.
  and the literal delpaths shard passes
  6/6, and iterator-fed destructuring shards pass 6/6. Dynamic path filters
  remain deferred pending a resumable
  contract. Filter-parameter validation is a textual module-loader bridge;
  general lexical calls, closures, and recursion remain deferred to the VM
  call-frame contract.
- The `atanh` focused shard passes 4/5 selected cases; one ordinary finite
  value is explicitly skipped for the known native-number last-digit spelling
  difference. The full catalog does not increase because the upstream atanh
  cases are embedded in broader unsupported expressions.

## Remaining high-value clusters

## CLI transplant measurement (2026-08-12)

The reviewed CLI vertical slice `eba8cfb8` was replayed cleanly onto the
current integration base `c2e7846d` as `4468b49c`. It builds and runs, but its
full pinned-oracle catalog measures **296/522 passed and 226 failed**. The
current integration head `565793ee` independently measures **324/522 passed
and 198 failed**. The transplant is therefore retained as an audited source
of CLI changes, not merged wholesale: it replaces newer evaluator/program
state and regresses the measured compatibility baseline. Future CLI work must
be replayed as smaller driver-owned commits and remeasured against this head.

The largest remaining groups are not all independent builtins. They include
dynamic indexes and slices, path mutation/assignment, richer binding and
module forms, generator/control-flow combinations, and process/codec APIs.
These need separate AST/program/evaluator contracts rather than parser-only
patches. In particular, dynamic indexes and assignment must establish value
path ownership before they are parallelized; otherwise lanes can appear to
pass isolated syntax tests while corrupting evaluator state.

## Repeating the measurement

Build the candidate with the pinned Odin toolchain, run the package checks and
CLI harness, then run the full catalog. Every new lane should add a focused
`compat/*.jq.test`, an explicit skip manifest for unsupported cases, and a
decision/evidence note with `path:line` citations. Review lanes should compare
only the merge-base-to-head diff and attempt to falsify the focused shard
before integration.
- Scalar non-string `ltrimstr`/`rtrimstr`/`trimstr` separators are now parsed
  and produce jq-compatible catchable type errors; focused shard passes 8/8.

## Latest integration snapshot (2026-08-12)

The current integration head (`d1f3001d`) measures **350/522 passed and 172
failed**, with zero harness errors. This includes the bounded zero-argument
definition/call path, declaration-time redefinition snapshots, bounded
recursive-call activation with a depth guard, and the materialized path-index
diagnostic. `make validate` passes all package, layout, oracle, and CLI checks
(333 subprocess and 43 differential cases). General parameterized calls,
closures, and generator-valued definitions remain separate VM call-frame work.

The subsequent parameterized-definition routing commit (`42f4bfca`) raises the
fresh catalog measurement to **355/522 passed and 167 failed**, with zero
harness errors. Its focused shard covers six-argument, generator-valued, and
`$` value-parameter definitions; general closures, nested lexical definitions,
and broader generator calls remain open.

The bound-path deletion slice (`bd17564a`) raises the fresh catalog to
**357/522 passed and 165 failed**, with zero harness errors. It covers
`delpaths([$p])` after an array-valued lexical path binding and preserves the
copy-on-write ownership contract; `make validate` remains green.

The nested data-import alias slice (`cd632dcf`) raises the fresh catalog to
**362/522 passed and 160 failed**, with zero harness errors. Qualified aliases
such as `$d::d[].this` and object shorthand imports now preserve stream
postfixes; full `make validate` remains green.

The NaN slice/index lane (`70085e6c`) is integrated in this snapshot;
`.[nan:1]`, `.[1:nan]`, and `.[nan]` now follow jq's null/endpoint behavior.

The NaN assignment diagnostic (`4bdd9c5c`) is present in the current head;
the fresh authoritative catalog now measures **363/522 passed and 159 failed**
with zero harness errors. `try ([range(3)] | .[nan] = 9) catch .` now reports
jq's `Cannot set array element at NaN index` result.

The literal walk compatibility slice (`95e733b0`) raises the authoritative
catalog to **366/522 passed and 156 failed**, with zero harness errors. It
covers `walk(.)`, `walk(1)`, and `[walk(.,1)]`; general post-order walk filters
remain deferred to a recursive evaluator continuation contract. Full package
validation and the CLI harness (333 subprocess / 43 differential checks) pass.

## Authoritative restored-CLI measurement (2026-08-14)

The reviewed CLI integration branch was restored at `28cb5463` and replayed
with the accepted evaluator/language chain through `869a9508` (dynamic slice
bounds, piped generator destructuring, dynamic trimstr, label/break control
flow, and the debug diagnostic event). The candidate built with Odin
`dev-2026-05`; `make check-packages` and `make test` passed all package and
external-boundary suites. Focused compatibility shards passed 7/7 for dynamic
slices, 2/2 for piped destructuring, 3/3 for dynamic trimstr, 3/3 for
label/break, and 1/1 for debug. The pinned jq 1.8.1 catalog selected all 522
cases and reports **426 passed, 96 failed, 0 harness errors**. The subsequent
trimstr typed-input error propagation fix (commit `3db4cdde`) adds exact
`ltrimstr`/`rtrimstr` diagnostics for non-string bases under `try`; the
focused trimstr shard is now 7/7. Static field assignment now preserves jq's
null-as-empty-object behavior and typed non-object diagnostics (`4b39bd66`),
and single-slot array rebinding is covered by a focused 4/4 shard
(`869a9508`). Nested static path components are now covered by the
`path-nested-static-component` shard and the exact `jq.test:1130` case. The
pinned catalog now reports **441 passed, 81 failed, 0 harness errors**. The
bounded `.sum = add(.arr[])` update is covered by the `sum-field-update` shard
and reuses existing object-addition semantics. The resumable uppercase
`IN(generator)` and `IN(source; s)` paths are covered by the `in-dynamic`
shard; `inside` remains deferred as a separate containment contract. The
parenthesized label delimiter fix covers the constructor forms at
`jq.test:315/319`; broader label/foreach update forms remain deferred. The
The bounded jq.test:333 foreach label-break update now passes through the
materialized accumulator/extraction path, and jq.test:2255's literal binding
initializer is covered by the same three-clause foreach shard. The remaining
failures are primarily richer destructuring/foreach, update-path assignment,
`?//`, module closures, dynamic builtins, process I/O, and exact diagnostics;
these remain implementation work rather than skipped coverage.

## Tuple-key follow-up (2026-08-14)

The current integration head (`a9235f69`) measures **467/522 passed, 55
failed, 0 harness errors**. The static keyed materialization lane accepts
comma-separated static tuple selectors in `sort_by(.a,.b)` and
`group_by(.a,.b)`, plus bounded arithmetic/comparison expressions such as
`group_by(.a + .b - .c == 2)`; the focused keyed shard passes 5/5 against jq
1.8.1. Variables, postfix paths, dynamic key expressions, generator-valued
keys, and the remaining composite sort/group forms remain deferred.

## Literal getpath assignment follow-up (2026-08-14)

The current head also accepts the bounded scalar form
`getpath(["a",0,"b"]) |= 5`, lowering it to the existing copy-on-write
`Setpath` evaluator. The jq.test:1241-shaped fixture passes 2/2, including
catchable typed number/object path errors. Dynamic path filters, variable
paths, and generator-valued RHS updates remain deferred.

## `with_entries` lowering follow-up (2026-08-14)

`with_entries(filter)` now lowers to the real
`to_entries | map(filter) | from_entries` instruction pipeline. The focused
key-prefix and composition shard passes 3/3, and jq.test:1683 now passes in
the full catalog. Non-object diagnostic wording and richer generator-valued
entry updates remain deferred.

## Multi-index empty deletion follow-up (2026-08-14)

The bounded selector form `.foo[1,4,2,3] |= empty` now lowers to the existing
`Delpaths` copy-on-write evaluator. Numeric selectors are ordered descending
before deletion so their coordinates remain anchored to the original array;
the jq.test:1261-shaped case passes against jq 1.8.1. Signed, fractional,
dynamic, slice, and filter-valued selector updates remain deferred under the
general path-update contract.

## Static deletion path-product follow-up (2026-08-14)

Nested static field/index chains and Cartesian products of static path streams
now lower to the existing `Delpaths` ABI. The complete jq.test:1168 expression
passes, including `del(.)`, `del(empty)`, piped numeric selectors, and nested
`.baz.bar[0].x`; dynamic keys, slices, and filter-valued path updates remain
deferred.

## Root index-field filter update follow-up (2026-08-14)

The bounded form `.[nonnegative-index].field |= FILTER` now has a dedicated
copy-on-write evaluator path. It handles null/missing array extension, empty
RHS deletion/no-op behavior, first-output cardinality, late-error cancellation,
and typed scalar/object/index errors. The focused shard passes 10/10 and adds
jq.test:1232-shaped coverage; general nested paths and dynamic selectors remain
deferred.

## Nested field-index-field filter update follow-up (2026-08-14)

The next bounded path form `.field[nonnegative-index].field |= FILTER` now has
its own four-operand continuation. It preserves nested-field deletion inside an
array element, synthesizes missing/null intermediates, cancels later RHS output
after the first update, and reports typed intermediate failures. The focused
shard passes 10/10; dynamic selectors, slices, and parameterized callable
updates remain deferred.

## One-argument callable activation follow-up (2026-08-15)

The evaluator now activates a bounded one-argument callable frame for the exact
`def id(x): x; id(...)` shape. Argument filters execute in Odin, generator
cardinality is preserved (`id(1,2)` emits two values), semicolon/zero-argument
misuse is rejected, and other parameterized definitions remain on the legacy
bridge. The focused shard passes 4/4; this does not yet claim general
parameterized lexical definitions.

## Simple callable arithmetic follow-up (2026-08-15)

The direct Odin callable route now also admits one parameterized definition
whose body is an additive tree of the parameter and numeric literals. This
covers `inc(x): x+1` and `twice(x): x+x` without broad textual expansion;
unsupported bodies continue through the legacy bridge. The focused arithmetic
shard passes 3/3, while general filter-valued callable bodies remain deferred.

## Destructuring alternation follow-up (2026-08-15)

The current reviewed implementation head (`34a009d1`) measures **494/522
passed, 28 failed, 0 harness errors** against the pinned jq 1.8.1 catalog.
The bounded alternation runtime preserves array-pattern branch rollback and
handles `. as [$a] ?// [$b] | .` for arrays and `null`, with jq-compatible
indexed-type diagnostics for non-array inputs. Existing object-pattern
permutations remain on their specialized lowering path; regression fixtures
cover those permutations. Array/object pattern captures visible in the body,
literal patterns, generators, and general multi-output rollback remain
deferred under the branch-scope ABI decision. The repeated same-name
object-pattern form `{a:$a} ?// {a:$a} ?// {a:$a}` is also covered, including
generator-fed inputs; the focused alternation shard is 15/15.
