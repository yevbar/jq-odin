# Regex compatibility case inventory

This inventory scopes later executable cases for jq 1.8.1 regex parity. The
pinned oracle is jq commit `4467af7068b1bcd7f882defff6e7ea674c5357f4`
with bundled Oniguruma commit `4ef89209a239c1aea328cf13c05a2807e5c146d1`.
Case IDs below are prospective and do not claim current Odin support.

## Imported fixture clusters

| Case ID prefix | Behavior | Provenance | Required comparison |
|---|---|---|---|
| `regex-onig-match-*` | Result shape, ASCII and Unicode offsets, named, unmatched, and empty captures | `upstream/jq/tests/onig.test:1-77` | Ordered semantic JSON stream plus exact status and stderr |
| `regex-onig-sub-*` | First/global substitution, replacement streams, zero-width, greedy/lazy, named capture context, UTF-8 | `upstream/jq/tests/onig.test:80-193` | Ordered semantic JSON stream plus exact status and stderr |
| `regex-onig-split-*` | Empty/no-match/case-insensitive delimiter behavior and boundary pieces | `upstream/jq/tests/onig.test:195-210` | Ordered semantic JSON stream plus exact status and stderr |
| `regex-man-match-*` | Manual examples for flags, match order, capture and test | `upstream/jq/tests/manonig.test:9-43` | Ordered semantic JSON stream plus exact status and stderr |
| `regex-man-scan-*` | Whole-match versus grouped scan output and ordering | `upstream/jq/tests/manonig.test:45-54` | Ordered semantic JSON stream plus exact status and stderr |
| `regex-man-split-*` | Collected split and streamed splits, including `n` | `upstream/jq/tests/manonig.test:1-3,56-72` | Ordered semantic JSON stream plus exact status and stderr |
| `regex-man-sub-*` | Named replacements and replacement streams | `upstream/jq/tests/manonig.test:74-88` | Ordered semantic JSON stream plus exact status and stderr |

The immutable fixtures are used in place. A future adapter should parse the
same jq-test format and retain each source `path:line`; it must not copy these
fixtures into `compat/`.

## Focused boundary additions

| Case ID | Input and filter | Oracle requirement | Evidence |
|---|---|---|---|
| `regex-flags-all` | Exercise `gimxspln`, duplicates, null, and empty flags | Each flag maps independently; `p` combines `m` and `s`; duplicates are accepted | `upstream/jq/src/builtin.c:931-969` |
| `regex-flags-invalid` | `"a" | match("a"; "z")` | Exit 5; exact stderr contains `z is not a valid modifier string` | `upstream/jq/src/builtin.c:961-966` |
| `regex-types-input` | `1 | match("a")` | Exit 5 with input-specific string type error | `upstream/jq/src/builtin.c:919-923` |
| `regex-types-pattern` | `"a" | match(1)` and one-argument array variants | Preserve wrapper-level versus primitive-level error distinctions | `upstream/jq/src/builtin.jq:81-94`; `upstream/jq/src/builtin.c:925-929` |
| `regex-types-flags` | `"a" | match("a"; 1)` | Exit 5 with modifier type error | `upstream/jq/src/builtin.c:970-975` |
| `regex-compile-error` | `"a" | match("(")` | Exit 5; exact Oniguruma-derived diagnostic is `Regex failure: end pattern with unmatched parenthesis` | `upstream/jq/src/builtin.c:979-989` |
| `regex-search-order` | `"baaa" | [match("a|aa"; "g")]` | Three length-one results at offsets 1, 2, 3 in order | `upstream/jq/src/builtin.c:996-1001,1090-1103` |
| `regex-longest` | `"aa" | match("a|aa"; "l")` | String is `aa` | `upstream/jq/src/builtin.c:955-957` |
| `regex-test-short-circuit` | A matching pattern with `g` and captures under `test` | One boolean, no match objects or later search | `upstream/jq/src/builtin.c:990-1005` |
| `regex-empty-ascii` | Existing empty-pattern and optional-group fixtures | Every ASCII boundary appears; participating empty and unmatched captures differ | `upstream/jq/tests/onig.test:1-12,40-64` |
| `regex-empty-multibyte` | `"é" | [match(""; "g")]` | Three complete empty records with exact ordered offsets `[0,1,1]`; raw search positions are bytes 0, 1, and 2, so the interior and terminal byte positions both map to visible offset 1 | `upstream/jq/src/builtin.c:1007-1036,1103` |
| `regex-empty-multibyte-capture` | `"é" | [match("(?<empty>)"; "g")]` | Three empty matches and three participating named empty captures; both match and capture offsets are `[0,1,1]`, all lengths are zero, and all strings are empty | `upstream/jq/src/builtin.c:1007-1033,1103` |
| `regex-empty-four-byte-restart` | `"😀" | [match(""; "g") | .offset]` | Exact ordered offsets `[0,1,1,1,1]`, proving one result for every bytewise restart position rather than every codepoint boundary | `upstream/jq/src/builtin.c:1007-1036,1103` |
| `regex-multibyte-capture-range` | `"aéz" | match("(?<x>é)")` | Whole match and named capture both have offset 1, length 1, and string `"é"`; their nonempty byte ranges retain UTF-8-aligned endpoints | `upstream/jq/src/builtin.c:1039-1089` |
| `regex-lookahead-once` | `"qux" | gsub("(?=u)"; "u")` | `quux`, without repeating the same zero-width match | `upstream/jq/tests/onig.test:128-130` |
| `regex-codepoint-spans` | Combining mark, non-ASCII, and embedded NUL | Offsets and lengths count codepoints; strings preserve NUL | `upstream/jq/tests/onig.test:22-34`; `upstream/jq/src/builtin.c:1039-1085` |
| `regex-invalid-raw-utf8` | Raw slurp bytes `ff 41 0a`, then match `A` and U+FFFD | Input becomes `"�A\n"`; `A` offset is 1 and replacement-character offset is 0 | `upstream/jq/src/jv.c:1112-1133,1278-1282` |
| `regex-named-duplicate` | `"ab" | match("(?<x>a)(?<x>b)")` and `capture` | Match retains two ordered records named `x`; capture object resolves `x` to `b` | `upstream/jq/src/builtin.c:893-908`; `upstream/jq/src/builtin.jq:90` |
| `regex-no-onig` | Candidate built without the foreign engine | Exact unavailable-library runtime error for every public wrapper | `upstream/jq/src/builtin.c:1111-1119` |
| `regex-depth-limit` | Nested single-capture pattern at depths 511 and 512 | Depth 511 succeeds; depth 512 exits 5 with `Regex failure: parse depth limit over` under the configured limit of 1024 | `upstream/jq/src/main.c:301-310` |

## Adapter and comparison requirements

- Preserve ordered output streams. `match`, `scan`, `splits`, and replacement
  filters are generators; set comparison would hide semantic failures.
- Compare exit status and stderr bytes exactly for type, modifier, compile,
  search, depth-limit, and unavailable-engine errors. Oniguruma version drift
  can change these messages and is therefore observable.
- Feed invalid UTF-8 and embedded NUL as encoded bytes, not through shell
  variables. Record canonical Base64 input as the process catalog does.
- Keep raw search cursors distinct from returned nonempty byte ranges. Binding
  tests must accept every bounded byte cursor and preserve empty positions even
  inside a codepoint; neutral-contract tests must reject a nonempty range whose
  endpoint splits UTF-8. Eval and compatibility tests must retain record
  cardinality and apply jq's exact raw-position-to-codepoint conversion without
  deduplicating equal visible offsets.
- Record the oracle executable hash and the Oniguruma artifact identity. A
  report that proves only the jq executable path is insufficient for this
  foreign-library boundary.
- Keep resource-limit probes (parse depth and pathological runtime patterns)
  in disposable, credential-free runners with explicit time and output bounds.

## Executed inventory checks

On 2026-08-03 the freshly built pinned oracle reported `jq-1.8.1` and passed:

- `jq --run-tests upstream/jq/tests/onig.test`: 47 of 47;
- `jq --run-tests upstream/jq/tests/manonig.test`: 19 of 19;
- direct probes for the focused cases above, except the compile-time no-Onig
  variant. In particular, exact multibyte probes produced three empty matches
  and captures at offsets `[0,1,1]` for `é`, five offsets `[0,1,1,1,1]` for
  `😀`, and a valid nonempty `é` whole-match/capture range at offset 1 and
  length 1. The nested-capture parse-depth probe accepted 511 and rejected 512.

No Odin regex candidate or regex compatibility adapter exists yet, so this
inventory records expected cases rather than candidate pass results.
