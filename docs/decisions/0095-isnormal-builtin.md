# Decision 0095: bounded `isnormal` builtin

Implement zero-argument `isnormal` as an operand-free builtin. It returns true
for finite, non-zero binary64 values with magnitude at least the IEEE-754
minimum-normal threshold, and false for zero, subnormal, NaN, infinity, and
non-number values. The AST and opcode discriminants are appended after `join`
to preserve serialized program compatibility.

Dynamic arguments and number representations other than the current binary64
value contract remain unsupported. jq's source classification is
`upstream/jq/src/builtin.c:1199-1207`; registration is at
`upstream/jq/src/builtin.c:1924-1927`.
