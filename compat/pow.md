# `pow` compatibility shard

This shard covers the zero-context two-argument numeric `pow(base; exponent)`
builtin, including negative and fractional literal exponents. Dynamic and
non-numeric argument diagnostics remain deferred.

Evidence: the upstream jq regression exercises `pow` in
`upstream/jq/tests/jq.test:2025-2029`; this bounded shard isolates the builtin
from the surrounding generator and binding expressions.
