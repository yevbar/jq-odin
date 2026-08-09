# Decision 0034: Preserve jq framing for module subtraction errors

## Status

Accepted for the CLI/module-loader compatibility slice.

## Decision

The module loader's temporary subtraction runtime key is translated at the CLI
boundary to jq 1.8.1's stdin diagnostic framing:

`jq: error (at <stdin>:1): string ("...") and number (1) cannot be subtracted`

Other runtime failures retain the Odin CLI diagnostic prefix until their jq
source-compatible framing is implemented by a dedicated compatibility slice.

## Evidence

- `cmd/jq-odin/main.odin:184-202` recognizes the private module key and emits
  the jq framing before the generic `jq-odin` error path.
- `cmd/jq-odin/test_cli.py:166-180` compares recursive module subtraction
  diagnostics against the pinned jq oracle.
