# Decision 0262: preserve literal postfix indexes during module filter expansion

The module loader continues to expand filter parameters textually until the
callable-definition IR exists. When a filter parameter is used directly inside
an index (`.[x]`), grouping a literal argument would produce `.[("a")]` or
`.[(0)]`, which the current syntax slice does not accept even though jq accepts
the equivalent literal forms `.["a"]` and `.[0]`. The loader therefore omits
grouping only for a lexically complete JSON scalar literal in this exact
postfix-index position; expression arguments retain grouping and remain
deferred. Oracle-backed coverage is in
`cmd/jq-odin/test_cli.py:438-455`, with expansion invariants in
`src/driver/driver_test.odin`.

This is a bounded compatibility bridge, not general callable-definition
semantics: recursive calls, closures, and dynamic index expressions still
require the future program/evaluator call contract.
