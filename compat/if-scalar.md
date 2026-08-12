# Scalar `if` compatibility

This shard covers literal and scalar-input conditionals. Truthiness follows
jq: only `false` and `null` select the else branch. Generator conditions,
`elif`, and dynamic continuation forms remain deferred.

Oracle evidence: `upstream/jq/src/compile.c` conditional lowering and
`upstream/jq/tests/jq.test` scalar conditional cases.
