# Dynamic arithmetic range bounds

The bounded evaluator accepts numeric identity/literal operands and arithmetic
expressions composed from them for `range` bounds. Each bound is evaluated
against the current input as a pure numeric expression, so map inputs retain
jq's per-element stream cardinality. General generator-valued bounds remain
deferred.

Evidence: `upstream/jq/tests/jq.test:287-303` and dynamic range cases in the
map/range compatibility cluster.
