# Callable filter-valued identity update

This fixture covers the bounded `def id(x): x |= .; id(.a)` ABI slice. The
argument remains a literal field filter, while the evaluator retains the
caller root for copy-on-write update and jq-compatible typed errors.
