# Decision 0252: boolean `and`/`or`

Lower `and` and `or` into append-only opcodes and evaluate jq truthiness. A
truthy left operand short-circuits `or`, and a falsey left operand short-circuits
`and`, independently for each output of a left-hand stream; this preserves jq's
observable cardinality and avoids evaluating a right-hand error when it is not
needed. This remains a bounded scalar/composite expression slice; dynamic
continuation forms outside the existing binary frame are deferred.
