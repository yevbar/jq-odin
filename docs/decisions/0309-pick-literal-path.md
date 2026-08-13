# Decision 0309: bounded literal pick path

The catalog case `pick(.a.b.c)` requires an object-shaped path result when the
input is null. The current path and setpath implementations already provide
the required owned copy-on-write construction for a literal path. The driver
therefore lowers exactly this whole-filter shape to `setpath(["a","b","c"]; null)`.
Dynamic pick filters and arbitrary path generators remain evaluator contracts.

Evidence: `upstream/jq/tests/jq.test:1184` and
`compat/pick-literal-path.jq.test`.
