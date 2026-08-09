# Decision 0033: Frame data-module streams and expose CLI validation

## Status

Accepted for the CLI/module-loader vertical slice.

## Decision

The module-data scanner treats `{` and `[` as boundaries after scalar values,
so adjacent JSON values such as `1[2]` become two members of the imported array
(` [1,[2]] `), matching jq's stream framing. Search-path arrays are destroyed
for every metadata form, including ordinary `include`/`import` directives with
empty metadata; only owned metadata entries are freed.

Decoded temporary keys are destroyed before the helper returns, with one
retry when an allocator reports a transient cleanup failure. This keeps the
decoded value owner reachable until cleanup succeeds.

`make validate` invokes the subprocess CLI suite after building a candidate and
the pinned jq oracle. The suite's standalone import fallback accepts those
already-authenticated paths when optional Vers isolation helpers are absent.

## Evidence

- `src/driver/module_loader.odin:245-252` frames adjacent scalar/container
  values.
- `src/driver/module_loader.odin:1650-1820` destroys every allocated search
  path array.
- `src/driver/module_loader.odin:326-353` retries decoded-key cleanup.
- `Makefile:38-66` builds and runs `cmd/jq-odin/test_cli.py` in validation.
- `cmd/jq-odin/test_cli.py:28-43` supports direct authenticated oracle paths.
