# Coverage next-lane evidence

Status: investigation recorded (2026-08-13)

The latest authoritative catalog is **417/522 passed, 105 failed, 0 errors**
(`/tmp/coverage-meta-object.json`, rebuilt after a green `make validate`). The
modulemeta bridge now covers the scalar projections and the canonical full
objects for modules `a` and `c`; the object bridge is deliberately bounded to
the two source-level constant forms present in the jq module fixtures.
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
