# Decision 0197: bounded first/last generator forms

`first(generator)` now returns the first value emitted by its child and
suppresses the remainder. `last(generator)` retains each child value and emits
the final one after child exhaustion; both preserve an empty child as an empty
stream. Zero-argument array selectors remain unchanged (and still return null
for empty arrays).

The evaluator adds explicit stream-consumer phases and owns the retained
`last` value in the frame, releasing it through normal frame cleanup. This
keeps the continuation and ownership contract local to the evaluator while
reusing existing child-generator frames. Dynamic argument forms, assignment,
and broader control-flow builtins remain deferred.

Evidence: `upstream/jq/tests/jq.test:397-410`; jq defines the selectors in
`upstream/jq/src/builtin.jq:166-167`.
