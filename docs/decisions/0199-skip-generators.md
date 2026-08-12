# Decision 0199: bounded `skip` generators

Implement literal nonnegative `skip(count; generator)` over existing stream
producers. The evaluator discards exactly the requested prefix while retaining
the active producer for all later outputs. Dynamic counts, comma-separated
counts/generators, negative-count diagnostics, and broader control-flow forms
remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:377-389`.
