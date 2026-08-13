# Function definition call frames

This shard records the functional call boundary currently provided by the
driver's definition expansion: a zero-argument definition may produce either
one result or a generator stream, and the call executes against the caller's
input. The first two cases exercise `def f: .+1; f` and
`def f: ., .+1; f`; the final duplicate is retained as a regression for
repeated compilation/evaluation.

The implementation is intentionally limited to non-recursive definitions.
Recursive definitions still require evaluator-owned call frames rather than
textual expansion.
