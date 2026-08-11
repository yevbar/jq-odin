# Decision 0132: reduce object values with `add`

The evaluator's `Add_Builtin` now accepts object inputs and folds their values
in object iteration order using the existing owned `value_add` operation.
Empty objects produce null, matching jq. Array behavior and error cleanup are
unchanged; no AST, program, or package graph contracts change.

Evidence: `upstream/jq/tests/jq.test:749-766` anchors the add family;
`compat/add-objects.jq.test` records empty, numeric, string, array, and array
regressions.
