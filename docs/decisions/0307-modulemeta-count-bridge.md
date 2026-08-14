# Modulemeta metadata bridge

Status: accepted bounded compatibility slice (2026-08-13)

The driver now handles `modulemeta`, `modulemeta | .deps | length`, and
`modulemeta | .defs | length` for the canonical source-level module objects and
string module-name inputs. It reuses the
owned `module_metadata` extractor and reads the module through the borrowed
`-L` search-path slice. The slice is deliberately driver-only: it does not add
an AST, program opcode, or evaluator module-context field.

Oracle evidence: jq 1.8.1 with `-L upstream/jq/tests/modules` returns the
canonical `c` object, including six dependencies and two definitions, and the
`a` object with its `{version:1.7}` module constant. Missing modules and
non-string inputs retain jq's runtime error boundary and status. The source
object materializer is intentionally bounded to the constant forms present in
the jq module fixture (`{whatever:null}` and `{version:1.7}`); arbitrary module
expressions, projections, and nested runtime module contexts remain future
shared-contract work.
