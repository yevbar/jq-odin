# Decision 0200: bounded `nth` generator

Implement literal nonnegative `nth(index; generator)` with zero-based stream
selection. The evaluator discards preceding outputs, emits at most one owned
value, and cancels descendant frames after selection. Dynamic indexes,
comma-separated generators, negative indexes, and broader continuation forms
remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:393-405,425-425`.
