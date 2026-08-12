# Decision 0236: bounded literal `limit` continuation

Literal integer `limit` counts reuse the existing `Limit` IR and evaluator
frame. A comma generator lowers to the ordinary `Fork` continuation. When the
remaining count reaches zero, the limit frame destroys all producer frames
above itself, preventing later fork outputs and errors from running.

Zero and negative counts are resolved before a generator frame is pushed.
Negative numeric syntax continues to lower to an ordinary signed numeric
literal, and the evaluator raises the existing catchable
`limit doesn't support negative count` runtime error. This matches
`upstream/jq/src/builtin.jq:142-145` and the early-termination cases at
`upstream/jq/tests/jq.test:365-375`.

The slice does not add an opcode, package edge, public type, label machinery,
or dynamic-count evaluation. General dynamic generators remain deferred.
