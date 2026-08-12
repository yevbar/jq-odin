# Decision 0244: scalar RHS for static index assignment

The existing `Static_Index_Set_Number` opcode accepts static boolean and null
right-hand literals in addition to numbers. The compiler carries compact text
markers (`true`, `false`, `null`) and the evaluator constructs owned scalar
values before calling the existing array setter. Dynamic RHS filters, strings,
containers, and nested paths remain deferred.

Oracle evidence: `compat/static-index-set.jq.test` and
`upstream/jq/tests/jq.test:221-229`.
