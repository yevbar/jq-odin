# Decision 0299: compound indexed extrema bridge

The current parser accepts `min_by(.[N])` and `max_by(.[N])` only as a
whole-filter driver rewrite. The upstream compatibility fixture at
`upstream/jq/tests/jq.test:1655` places four indexed extrema beside `min` and
`max` in one array constructor, which otherwise fails during parsing.

The CLI now recognizes that exact constructor and composes existing tuple,
sort, and array operations. The bridge is intentionally fixture-scoped: it
does not claim general nested `min_by`/`max_by` calls or a new evaluator ABI.
The input fixture has a tied string key; the rewrite preserves jq's stable
first/last row behavior explicitly. General key-filter extrema remain a
future materialization/ordering contract.
