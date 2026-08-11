# Odin CLI coverage snapshot

This is a coordinator snapshot for the accepted Odin CLI lineage, not a claim
of upstream jq compatibility. The immutable `upstream/jq` tree remains the
behavioral oracle.

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

## Remaining high-value clusters

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
