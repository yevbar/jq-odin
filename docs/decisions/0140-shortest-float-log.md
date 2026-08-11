# Decision 0140: native shortest-float normalization

The initial all-finite normalization was narrowed after it regressed existing
jq dtoa boundary cases (`jq.test:2169,2173,2177`). The serializer now requests
fifteen significant digits only for tiny native values (`|n| < 1e-10`), while
ordinary and large values retain the full-precision path. JSON owns this
formatter; the evaluator and value packages remain unchanged.

The targeted `log(2)`/`log(10)` text regressions are deferred because native
libm results differ before serialization; representative ordinary, tiny-
exponent, and large native values retain their prior parity.
