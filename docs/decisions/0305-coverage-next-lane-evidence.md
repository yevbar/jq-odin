# Coverage next-lane evidence

Status: investigation recorded (2026-08-13)

The latest authoritative catalog is **421/522 passed, 101 failed, 0 errors**
(`/tmp/coverage-mask.json`, rebuilt after a green `make validate`). The
modulemeta bridge now covers the scalar projections and the canonical full
objects for modules `a` and `c`; the object bridge is deliberately bounded to
the two source-level constant forms present in the jq module fixtures.
The static numeric slice-assignment lane adds the two cases at
`upstream/jq/tests/jq.test:2437` and `2441`, including jq's null/scalar error
boundaries and extreme-bound handling.
The remaining sort/group case at
`upstream/jq/tests/jq.test:1639` combines stable multi-key `sort_by` with
`group_by`; the current driver has narrow rewrites for standalone
`sort_by(.field)` and selected multi-key forms, but the full expression still
returns a filter parse error.

Before attempting another rewrite, direct probes showed that the existing
candidate cannot evaluate the nested `to_entries`/constructor materialization
needed for a stable-sort lowering, while a simpler `map([.a,.]) | sort |
map(.[1])` path works. This is evidence of a broader composite/materialization
contract gap, not a safe comparator-only patch.

The next VM packet should therefore either:

1. implement and adversarially review a first-class stable key-materialization
   path for `sort_by`/`group_by`, spanning parser/program/evaluator ownership; or
2. explicitly prove that the current IR can support that path without new
   shared contracts, then add the smallest validated rewrite.

Do not claim a coverage gain from parser-only admission or a driver rewrite
until the full jq.test:1639 stream (all five outputs and tie ordering) matches
the pinned oracle.

The generator-valued `contains` lane is now integrated and independently
reviewed. It passes the focused jq.test:1615 and :1619 cases, including direct
and caught type-mismatch diagnostics and child-generator errors. The full
catalog remains 419/522 because those forms are not selected by the catalog
runner; the authoritative report is still `/tmp/coverage-contains.json` with
no harness errors. This is a semantic lane completion, not a percentage gain.

The bounded three-clause `foreach` extractor lane is also integrated. It adds
the optional EXTRACT operand while preserving the four-operand ABI, and its
identity and identity-times-literal probes match jq. The catalog remains
419/522 (`/tmp/coverage-foreach.json`); the selected catalog does not include
the focused extractor forms, so this is another semantic gain without a
percentage change. General generator-valued extractors remain deferred.

The grouped static slice deletion mask subsequently adds the selected
`jq.test:474` and `:1175` cases, raising the catalog to 421/522. It resolves
comma selectors against the original array coordinate space and preserves
legacy scalar-only deletion lowering. Positive `nan` bounds remain a
documented parser gap.
