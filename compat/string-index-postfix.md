# Literal string bracket postfixes

This shard covers jq's literal string-key bracket form (`.["foo"]`) and
postfix chaining, including a missing key's `null` result. The syntax lowers to
the existing Field node/opcode, so no evaluator or ownership contract changes
are required. Interpolated keys, dynamic expressions, and assignment/update
forms remain deferred.

The first case is anchored to `upstream/jq/tests/jq.test:164-166`.
