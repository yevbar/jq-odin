# Decision 0218: bounded reducer binding/update

The evaluator recognizes one static reducer binding/update shape used by the
jq regression at `upstream/jq/tests/jq.test:2247-2249`. It unwraps a literal
binding seed and evaluates `. as $elif | . + $then * $elif` over array inputs.
This is deliberately structural; general reducer continuations, destructuring,
and dynamic bindings remain outside the slice.
