# Decision 0193: computed unary negation

Unary negation of a computed child is now lowered to an append-only `Negate`
opcode. The evaluator preserves generator cardinality, negates each numeric
child result, and raises a jq-compatible typed message for non-numeric values.
Literal numeric negation continues to use the existing canonical literal path.

Evidence: `upstream/jq/tests/jq.test:39` exercises computed negation and
`upstream/jq/tests/jq.test:1959` exercises its try/catch boundary.
