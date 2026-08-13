# Repeated `elif` chains

The parser lowers each `elif` arm to a nested `If` node, preserving the
existing compiler/evaluator conditional contract. An omitted final `else`
uses jq's identity fallback, including when the chain contains multiple
`elif` arms. This corresponds to the conditional cases in
`upstream/jq/tests/jq.test` around lines 1301–1337.
