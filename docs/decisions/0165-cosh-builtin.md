# Decision 0165: unary `cosh`

Add the zero-argument `cosh` numeric builtin using Odin's native hyperbolic
cosine implementation. Non-number diagnostics and platform-sensitive extreme
precision remain under the existing math-builtin policy.

Oracle evidence: `upstream/jq/tests/jq.test:830-850`.
