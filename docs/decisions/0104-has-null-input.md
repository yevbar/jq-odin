# Decision 0104: null input for literal `has`

Literal `has` now returns `false` for null input, regardless of the literal
key/index argument. Object and array wrong-key type errors remain runtime
errors; negative indexes remain parser-deferred because unary negation is not
yet lowered. This follows the jq null-input probes adjacent to
`upstream/jq/tests/jq.test:1687-1695`.
