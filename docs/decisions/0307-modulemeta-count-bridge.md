# Modulemeta scalar projection bridge

Status: accepted bounded compatibility slice (2026-08-13)

The driver now handles exactly `modulemeta | .deps | length` and
`modulemeta | .defs | length` for string module-name inputs. It reuses the
owned `module_metadata` extractor and reads the module through the borrowed
`-L` search-path slice. The slice is deliberately driver-only: it does not add
an AST, program opcode, or evaluator module-context field.

Oracle evidence: jq 1.8.1 with `-L upstream/jq/tests/modules` returns `6` and
`2` respectively for input `"c"`; missing modules retain the module error
boundary. The full metadata object, arbitrary projections, and nested runtime
module contexts remain future shared-contract work.
