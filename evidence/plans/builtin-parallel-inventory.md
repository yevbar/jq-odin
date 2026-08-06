# jq 1.8.1 builtin implementation inventory

This inventory partitions the requested builtin surface into non-overlapping,
dependency-ordered implementation batches. It is evidence and scheduling
material only: it does not choose Odin APIs, packages, or import edges. The
pinned source registers native builtins centrally at
`upstream/jq/src/builtin.c:1877-1963`, while a second layer is written in jq at
`upstream/jq/src/builtin.jq:1-243`. Those layers have materially different
cardinality and prerequisites.

## Reading the tables

- **one** means one value on success for one input; a native error is an invalid
  result with a message, not an ordinary output value.
- **zero-to-many** means the jq filter is a generator. Collection syntax may
  turn an inner stream into one array, but filter arguments can still branch or
  fail according to evaluator semantics.
- **optional** refers to `?` suppressing an error/absence in jq code, not to a
  separate native builtin mode.
- Fixture ranges identify existing pinned coverage. Recommended shards are
  future focused subsets of those fixtures plus explicit probes listed below;
  they do not change the compatibility case schema.

## Verified surface inventory

| Surface | Definition and fixture evidence | Results, errors, and ordering | Hard dependencies | Batch |
|---|---|---|---|---|
| `type` | `upstream/jq/src/builtin.c:1171-1175`; `upstream/jq/tests/man.test:460-462` | one; returns one of jq's kind names; no ordinary type error | value kinds | B1 |
| `length` | `upstream/jq/src/builtin.c:483-500`; `upstream/jq/tests/jq.test:728-730`; `upstream/jq/tests/man.test:199-205` | one; array/object count, Unicode codepoints, numeric absolute value, null -> 0; boolean errors | value containers, Unicode iteration, number backend | B1 |
| `keys`, `keys_unsorted` | `upstream/jq/src/builtin.c:797-811`; `upstream/jq/src/jv_aux.c:531-586`; `upstream/jq/tests/jq.test:741-743,1699-1701` | one; arrays yield ascending indices; `keys` sorts object keys by raw string byte ordering, `keys_unsorted` preserves object iteration order; other types error | array/object representation and iteration | B1 |
| `has` | `upstream/jq/src/jv_aux.c:241-265`; `upstream/jq/tests/jq.test:1687-1697` | one boolean; null -> false; object requires string key, array requires numeric key, NaN index -> false; other pairings error | value lookup and numeric index conversion | B1 |
| `tonumber`, `toboolean` | `upstream/jq/src/builtin.c:441-480`; `upstream/jq/tests/jq.test:697-714`; `upstream/jq/tests/man.test:442-452` | one; identity for already-correct kind; whole-string parse only; malformed or wrong kinds error | number parser/backend | B2 |
| `tostring`, `tojson`, `fromjson`, `utf8bytelength` | `upstream/jq/src/builtin.c:428-438,502-514`; `upstream/jq/tests/jq.test:106,732-738`; `upstream/jq/tests/man.test:454-458,714-722` | one; `tostring` preserves strings and compact-serializes other values; `tojson` always serializes; `fromjson` requires a string and exactly one JSON value; byte length differs from codepoint length | JSON parser/printer, number backend, UTF-8 storage | B2 |
| `map`, `map_values` | `upstream/jq/src/builtin.jq:3,34`; `upstream/jq/tests/man.test:236-250` | normally one collection; `map` preserves element order and concatenates every result of `f`; `map_values` uses update semantics and can delete members when `f` is empty | evaluator iteration, collection, update/path semantics | B3 |
| `reverse`, `flatten`, `join` | `upstream/jq/src/builtin.jq:44,65-71`; `upstream/jq/tests/jq.test:445-457,1757-1775`; `upstream/jq/tests/man.test:393-407,510-512,638-644` | one; reverse reverses iteration order; flatten is depth-first left-to-right and negative explicit depth errors; join preserves order, stringifies numbers/booleans, maps null to empty string, and rejects incompatible concatenation | B1-B2, evaluator reduce/iteration, arithmetic | B3 |
| `range/1`, `range/2`, `range/3` | `upstream/jq/src/builtin.jq:72,151-154`; `upstream/jq/tests/man.test:409-432` | zero-to-many, ordered from start by step while bound holds; wrong-signed step and zero step emit nothing | evaluator generator/recursion, comparison, arithmetic | B3 |
| `sort`, `sort_by` | `upstream/jq/src/builtin.c:813-829`; `upstream/jq/src/jv_aux.c:588-712`; `upstream/jq/src/builtin.jq:5`; `upstream/jq/tests/jq.test:1635-1645` | one; arrays only; total kind order comes from `jv_cmp`; arrays compare lexically, objects by sorted keys then values, NaN compares as null; stable for equal keys by original index | value comparison, arrays; evaluator for `sort_by` key filter | B4 |
| `group_by`, `unique`, `unique_by` | `upstream/jq/src/builtin.c:865-890`; `upstream/jq/src/jv_aux.c:714-760`; `upstream/jq/src/builtin.jq:6-7`; `upstream/jq/tests/jq.test:1639-1653` | one; arrays only; results are comparison-sorted, equal-key group members retain input order, and unique retains the first equal-key value after the stable sort | B4 comparison/sort; evaluator for key filters | B4 |
| `min`, `max`, `min_by`, `max_by` | `upstream/jq/src/builtin.c:1121-1167`; `upstream/jq/src/builtin.jq:8-9`; `upstream/jq/tests/jq.test:1655-1661` | one; arrays only; empty -> null; strict comparison retains the first equal-key item for min, while the max condition replaces on equality and retains the last equal-key item | B4 comparison; evaluator for key filters | B4 |
| `bsearch` | `upstream/jq/src/builtin.c:831-863`; `upstream/jq/tests/jq.test:1789-1803` | one index; sorted arrays return the matching index or `-1-insertion_point`; non-arrays error, and unsorted input has no specified useful result | value comparison and array indexing | B4 |
| `path`, `paths` | `upstream/jq/src/builtin.c:2016-2018`; `upstream/jq/src/execute.c:228-270,629-677`; `upstream/jq/src/builtin.jq:51-52`; `upstream/jq/tests/jq.test:1101-1136` | zero-to-many; `path(.)` emits `[]`; `paths` omits the empty root path and follows recursive traversal order; invalid path-producing expressions error | compiler PATH opcodes, resumable evaluator path state, iteration | B5 |
| `getpath`, `setpath`, `delpaths` | `upstream/jq/src/builtin.c:1372-1378`; `upstream/jq/src/jv_aux.c:378-527`; `upstream/jq/tests/jq.test:1138-1182` | one; path must be array; empty get returns root, empty set replaces root; missing traversal can materialize null-filled containers; delpaths sorts paths, empty list is no-op, root path yields null; malformed paths error | value indexing/mutation; `getpath` also reports traversal to evaluator path state | B5 |
| `del`, `pick` | `upstream/jq/src/builtin.jq:12,223-227`; `upstream/jq/tests/jq.test:1168-1199` | one for each input; `del` lowers to `delpaths([path(f)])`, while `pick` reduces selected paths into a null-rooted result and propagates path errors | path evaluation, get/set/delpaths, reduce/update | B5 |
| `startswith`, `endswith`, literal `split`, `indices` | `upstream/jq/src/builtin.c:252-284,1274-1279,1288-1290`; `upstream/jq/src/builtin.jq:45-48`; `upstream/jq/tests/jq.test:1486-1501,1515-1557,2460-2486` | one; byte-preserving starts/ends and literal split reject non-strings; `indices` dispatches to array or string indexing and preserves every match in order | string/array storage and indexing | B6 |
| `ltrimstr`, `rtrimstr`, `trimstr`, `trim`, `ltrim`, `rtrim` | `upstream/jq/src/builtin.jq:77-79`; `upstream/jq/src/builtin.c:1292-1342`; `upstream/jq/tests/jq.test:1503-1541` | one; substring trims only when prefix/suffix matches; whitespace trims use jq's Unicode whitespace classification; wrong types error | B1 length/slicing; Unicode whitespace | B6 |
| `explode`, `implode` | `upstream/jq/src/builtin.c:1281-1286,1344-1369`; `upstream/jq/tests/jq.test:2358-2367`; `upstream/jq/tests/man.test:630-636` | one; explode returns codepoints in order; implode requires numeric, non-NaN elements, truncates fractions, and substitutes U+FFFD for invalid scalar values | Unicode decode/encode, arrays, numbers | B6 |
| `ascii_downcase`, `ascii_upcase` | `upstream/jq/src/builtin.jq:190-194`; `upstream/jq/tests/jq.test:1785-1787`; `upstream/jq/tests/man.test:646-648` | one; only ASCII A-Z/a-z change; all other codepoints retain order and value; dependency errors propagate | B3 map, B6 explode/implode, arithmetic | B6 |
| regex `split/2`, `splits`, `match`, `test`, `capture`, `scan`, `sub`, `gsub` | `upstream/jq/src/builtin.jq:80-130`; `upstream/jq/src/builtin.c:893-1118` | mixed: match/scan/splits/sub/gsub can be zero-to-many; split collects; invalid regex/modifier/type errors; match order and captures come from Oniguruma | regex engine plus evaluator generators and B6 slicing | B9 |
| libm family, `isinfinite`, `isnan`, `isnormal`, `infinite`, `nan` | `upstream/jq/src/builtin.c:139-226,1177-1218,1880-1895,1924-1928`; `upstream/jq/src/libm.h:1-301`; `upstream/jq/tests/jq.test:821-849,2024-2030,2207-2235`; `upstream/jq/tests/man.test:434-440,464-472` | one; the configured matrix below exposes unary `/1`, two-argument `/3`, three-argument `/4`, and output-array `/1` wrappers; available wrappers require numeric operands, `_NO` wrappers return named build-time errors, and availability/results are platform/configuration dependent; predicates return false for non-numbers | number backend and target libm/configuration | B7 |
| `input`, `inputs` | `upstream/jq/src/builtin.c:1387-1398`; `upstream/jq/src/builtin.jq:184-188`; `upstream/jq/tests/jq.test:2293-2297`; `upstream/jq/tests/shtest:38-40,94` | input produces one value or error; exhaustion is internal `"break"`; inputs is zero-to-many in source order, suppresses only exhaustion, preserves embedded NUL in raw strings, and propagates other errors | CLI/runtime input callback, evaluator try/repeat | B8 |
| `debug`, `stderr` | `upstream/jq/src/builtin.c:1400-1416`; `upstream/jq/src/builtin.jq:229-230`; `upstream/jq/tests/shtest:273-275` | one unchanged jq value after invoking the selected message callback; `debug(msgs)` emits callback messages for every `msgs` result, discards them, then returns original input | CLI/runtime message callbacks and output formatting | B8 |
| `env`, `$ENV` | `upstream/jq/src/builtin.c:1224-1242`; `upstream/jq/tests/man.test:686-692` | one object snapshot; process iteration supplies insertion order; split at first `=`; environment-dependent fixture must set variables explicitly | process environment and object insertion | B8 |
| `recurse`, `walk` | `upstream/jq/src/builtin.jq:36-39,212-221`; `upstream/jq/tests/man.test:662-684`; `upstream/jq/tests/jq.test:2373-2390` | recurse is depth-first pre-order zero-to-many; no-arg recurse uses `.[]?`; walk is child-before-parent and object/array traversal preserves their iteration order. A root-level branching `f` can emit multiple results, but child branches are constrained by `map_values` update assignment for objects and `map` collection for arrays; they do not uniformly propagate as multiple enclosing values | evaluator recursion/generators, B1 type, B3 map/map_values | B10 |

## Dependency-ordered branch partition

Each batch is intended to be a separate narrowly reviewable implementation
branch after the CLI/runtime stack lands. A later coordinator may split a row
further, but should not combine rows across the stated gates.

| Batch | Owned behavior | Explicit prerequisites | Recommended compatibility shard |
|---|---|---|---|
| B1 scalar metadata | `type`, `length`, `keys`, `keys_unsorted`, `has` | stable value kinds, container iteration/indexing, Unicode codepoint count | `builtins-metadata`: jq.test 728-743, 1687-1701; man.test 199-225, 460-462; add wrong-kind and object insertion-order probes |
| B2 conversion | `tonumber`, `toboolean`, `tostring`, `tojson`, `fromjson`, `utf8bytelength` | value plus JSON parser/printer and selected number backend | `builtins-conversion`: jq.test 106, 697-714, 732-738, 2148-2207, 2273-2282, 2456; man.test 442-458, 714-722, 835 |
| B3 collection/generators | `map`, `map_values`, `reverse`, `flatten`, `join`, `range` | B1-B2; resumable evaluator, collection/reduce/update, arithmetic | `builtins-collection`: jq.test 445-457, 745-768, 1757-1775, 1976; man.test 236-250, 393-432, 510-512, 638-644 |
| B4 ordering | sort/group/unique/min/max families and `bsearch` | total value comparison and stable array sorting; B3 map for key collection | `builtins-ordering`: jq.test 1635-1661, 1789-1799; man.test 474-508, 698-700; add equal-key stability and mixed-kind probes |
| B5 paths | `path`, `paths`, `getpath`, `setpath`, `delpaths`, then `del`/`pick` wrappers | compiler PATH form, evaluator path state, value indexing/mutation, B3 reduce/update | `builtins-path`: jq.test 1101-1182, 1240-1242, 2450-2453, 2489-2492; man.test 252-298, 349-351 |
| B6 non-regex strings | starts/ends, literal split, trim families, explode/implode, ASCII case, indices | Unicode-safe value strings/slices, B1 length, B3 map | `builtins-string-core`: jq.test 1486-1541, 1785-1787, 2358-2371, 2460-2486; man.test 610-648 |
| B7 math | configured libm wrappers and numeric predicates/constants | final number backend and target libm policy | `builtins-math`: jq.test 821-849 (floor/sqrt/trig), 2024-2030 (pow/log2/round), 2207-2235 (abs/fabs/length); man.test 434-440, 464-472; use the matrix below for every configured name/arity, with availability probes per target |
| B8 process I/O | `input`, `inputs`, `debug`, `stderr`, `env`, `$ENV` | landed CLI/runtime callbacks, raw input framing, process environment, message rendering | `builtins-process-io`: jq.test 2293-2301; shtest 38-40, 70-96, 273-280; deterministic environment and EOF/error probes |
| B9 regex strings | match/test/capture/scan/splits/split-with-flags/sub/gsub | regex boundary, evaluator generators, B6 slicing | `builtins-regex`: `upstream/jq/tests/onig.test:1-78` (match/test/capture), `:80-193` (sub/gsub/scan), `:195-211` (splits), plus targeted empty/global/capture/error probes |
| B10 recursive helpers | `recurse` overloads and `walk` | evaluator recursion and zero-to-many semantics; B1, B3, B5 where used | `builtins-recursive`: jq.test 2373-2390; man.test 662-684; add deep nesting, empty step, multi-result step, and error probes |

### B7 generated libm matrix

`libm.h` is the complete configured-name inventory; each conditional pair is a
build-time availability decision, not a promise that every target exports the
function. The registration macros in `builtin.c:1880-1892` expose these source
wrappers with an internal `CFUNC` arity that includes jq's implicit input. The
table separates that input-inclusive count from the jq-visible explicit
argument arity used in user syntax. The `_NO` wrappers retain the name but
return a build-time error (`builtin.c:148-152,170-175,201-206,220-224`).

| CFUNC arity (including input) | jq-visible explicit arity | configured names | source entries | successful shape and type probe |
|---|---|---|---|---|
| `/1` | `/0` | `acos`, `acosh`, `asin`, `asinh`, `atan`, `atanh`, `cbrt`, `cos`, `cosh`, `exp`, `exp2`, `floor`, `j0`, `j1`, `log`, `log10`, `log2`, `sin`, `sinh`, `sqrt`, `tan`, `tanh`, `tgamma`, `y0`, `y1`, `ceil`, `erf`, `erfc`, `exp10`, `expm1`, `fabs`, `gamma`, `lgamma`, `log1p`, `logb`, `nearbyint`, `rint`, `round`, `significand`, `trunc` | `upstream/jq/src/libm.h:1-145,152-280` | numeric input -> one number; non-number probe: `"x" | sqrt` errors with `number required` when the function is available |
| `/3` | `/2` | `atan2`, `hypot`, `pow`, `remainder`, `jn`, `yn`, `copysign`, `drem`, `fdim`, `fmax`, `fmin`, `fmod`, `nextafter`, `nexttoward`, `scalb`, `scalbln`, `ldexp` | `upstream/jq/src/libm.h:26-104,146-165,192-215,242-285` | two numeric arguments -> one number; wrong argument kind errors; `jn`/`yn` have no `_NO` branch and therefore are omitted when unavailable |
| `/4` | `/3` | `fma` | `upstream/jq/src/libm.h:197-200` | three numeric arguments -> one number; wrong argument kind errors |
| `/1` output-array wrappers | `/0` | `modf`, `frexp`, `lgamma_r` | `upstream/jq/src/libm.h:287-300`; `builtin.c:209-224` | numeric input -> two-number array; wrong kind errors; unavailable entries return the named build-time error |

The non-libm math primitives are separate native entries: predicates and
constants are registered at `upstream/jq/src/builtin.c:1924-1928` and their
non-number behavior is implemented at `1177-1218`. The pinned fixtures sample
the family rather than exhaustively asserting one platform's libm: `jq.test`
uses `floor`/`sqrt`/trigonometry at `821-849`, `pow`/`log2`/`round` at
`2024-2030`, and `abs`/`fabs`/`length` at `2207-2235`. A compatibility shard
must enumerate the matrix above, record whether each configured name is
available on the target, and probe both successful numeric calls and wrong-kind
errors; it must not label the sampled fixture ranges as exhaustive coverage.

The batches intentionally do not create a builtin package boundary. The
documented package graph says builtins must not be split into packages until an
implementation slice demonstrates the dependency direction
(`docs/architecture/package-graph.md:31-33`). Production ownership and any
cross-package contract changes remain coordinator decisions.

## Coverage gaps and required probes

Existing fixtures give broad examples, but branch authors should add focused
differential cases for the following observable edges before claiming a batch
complete:

1. `keys_unsorted` object insertion/deletion order and non-container errors;
   boolean `length` errors; mismatched `has` key kinds and null behavior.
2. Leading/trailing whitespace and malformed suffixes for `tonumber`, plus
   decimal-backend-dependent literal preservation for all dump conversions.
3. Zero- and multi-result filter arguments for map/map_values and every
   `_by` wrapper; propagation of an error after earlier results.
4. Stable ordering for equal keys; mixed-kind comparison including NaN, nested
   arrays, and objects with identical keys inserted in different orders.
5. Empty, negative, slice, missing, and malformed path components; path state
   under backtracking and nested `path` calls.
6. Embedded NUL and multibyte strings across split/trim/explode/implode;
   invalid codepoints and fractional implode values.
7. For every row of the B7 libm matrix, probe numeric success, wrong-kind
   errors, domain/NaN/infinity/signed-zero behavior where meaningful, and the
   `_NO` unavailable-function error on every supported target configuration.
8. Input EOF versus parse/I/O error, message-channel bytes and ordering,
   duplicate/empty environment entries, and an explicitly controlled `$ENV`.
9. Recursive empty/multi-result/error steps and depth sufficient to expose
   evaluator stack or continuation limits.

10. Corrected-claim probes against pinned jq 1.8.1: equal-key
    `min_by`/`max_by` must return `["a","b"]`; child and root `walk` branching
    must return `{"a":1}` and `[{"a":1},2]`; `bsearch` must cover hit and
    insertion-point results; `onig.test` match/capture/sub/gsub/scan/splits cases
    must remain in B9; and B7 probes must distinguish available wrappers from
    named unavailable-function errors.

No current compatibility catalog assigns these proposed shard names. The
coordinator should add catalog entries only after the corresponding runtime
surface exists; this facts branch does not edit `compat/**` or the
coordinator-owned workstream table.
