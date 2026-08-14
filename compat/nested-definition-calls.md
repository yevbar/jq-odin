# Nested and lexical function definitions

`compat/nested-definition-calls.jq.test` is a focused oracle shard for the
four jq 1.8.1 cases that require first-class local definitions and callable
closures: `upstream/jq/tests/jq.test:775-778`, `:789-791`, `:864-866`, and
`:875-877`. The expected streams are copied from the pinned jq oracle; the
case comments identify the semantic pressure each probe applies.

This shard is intentionally separate from the existing zero-argument and
top-level redefinition fixtures. A conforming implementation must preserve
declaration-time visibility, nested shadowing, parameter/local binding frames,
and generator backtracking across call returns. Textual source expansion is
not sufficient because the same function body can be entered multiple times
with different lexical environments and stream cursors.
