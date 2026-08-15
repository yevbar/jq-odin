# Module import aliases with query-local definitions

The existing module loader handles multiple code/data imports and aliases when
the imported references are used directly. With `upstream/jq/tests/modules` on
the search path, direct alias forms produce `[`"a","b","c","a"`]` and the
duplicated data object as jq does. jq.test:1862 and :1879 add a query-local
`def` after those imports; pinned jq still succeeds, while the candidate
reports a filter parse error for both.

The loader strips leading import/include directives, collects aliases/data, and
expands module definitions (`src/driver/module_loader.odin:2335-2454`), but the
expanded query-local definition/qualified-reference shape is rejected before
execution. Import/include/module tokens are not represented as syntax/program
namespace nodes (`src/syntax/parser.odin:4170-4174`).

A sound implementation needs a compiler-facing namespace and definition-scope
contract preserving query-local definitions after import expansion, or a
verified expansion invariant with parser fixtures. Alias-specific textual
substitution risks name capture and data/code import precedence, so this
cluster remains deferred.
