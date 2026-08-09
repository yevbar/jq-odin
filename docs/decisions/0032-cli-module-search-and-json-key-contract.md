# Decision 0032: Own module search metadata and decode imported JSON keys

## Status

Accepted for the CLI/module-loader vertical slice.

## Context

The CLI module loader receives search metadata as a slice borrowed from the
filter source. A search-path array must outlive the parser call, so it cannot
retain that borrowed slice as storage it will later release. This was
observable when `include "foo" {"search":"./lib"}; ...` was used without a
`-L` path: the first search entry was the borrowed metadata string, but cleanup
treated it as owned memory.

Imported JSON modules are parsed JSON, not textual maps. JSON object member
names are decoded before lookup, so an imported key encoded as `"\\u0078"`
must be found by the jq field `.x`.

## Decision

`module_search_paths` clones every metadata search entry when it does not build
an owned joined path. `destroy_module_search_paths` therefore releases the
first entry whenever metadata supplied one; no caller filter storage is freed.

For data-module postfix fields, the loader asks the pinned JSON parser to
decode each candidate object key before comparing it to the jq identifier. It
continues to return the original JSON literal for the matched value, preserving
the existing compiler/lowering ownership path while making key comparison
semantically JSON-aware.

The `cmd/jq-odin` package and its Odin tests are part of `make check` and
`make test`, so CLI changes cannot bypass package compilation or focused test
execution.

## Evidence

- `src/driver/module_loader.odin:506-548` owns/clones metadata search paths and
  releases only those owned entries.
- `src/driver/module_loader.odin:322-399` decodes candidate JSON keys through
  `jq:json` before field lookup.
- `cmd/jq-odin/test_cli.py:182-280` covers no-`-L` relative metadata and an
  escaped JSON key, both compared against jq 1.8.1.
- `src/driver/driver_test.odin:437-470` verifies allocator cleanup with and
  without `-L` paths.
- `Makefile:8-18` and `Makefile:35-44` compile and run `cmd/jq-odin`.

## Consequences

The loader performs a bounded parse of each candidate key, adding small setup
work only for imported data postfixes. In exchange, it follows jq/JSON key
semantics and makes ownership explicit at the CLI boundary.
