# Decision 0194: negative array index reads

Literal negative numeric postfix indices are accepted and resolved relative to
the end of arrays (`.[-1]` is the final element). Out-of-range negative reads
yield `null`, matching jq. This is a read-only contract: negative index
assignment and dynamic index expressions remain deferred. Literal slice bounds
use the separate bounded read contract in Decision 0204.

Evidence: `upstream/jq/src/jv_aux.c:93-106` specifies numeric array read
normalization and the out-of-range `null` result. Assignment boundaries at
`upstream/jq/tests/jq.test:213-229` are intentionally outside this slice.
