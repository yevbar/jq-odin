# Decision 0174: preserve zero-divisor diagnostics

## Scope

Numeric division and remainder by zero now carry jq-compatible operand text in
the owned runtime key. This covers both literal and input-derived numeric
operands while leaving successful arithmetic unchanged.

## Evidence

The sixth case in `compat/runtime-error-keys.jq.test` covers division and
remainder, including `0/0`. The combined shard passes 6/6 against pinned jq
1.8.1. The corresponding oracle cases are
`upstream/jq/tests/jq.test:2004-2020`.

## Ownership and limits

The key is built before the binary frame releases its operands, copied by
`raise_runtime`, and freed after retention. Nonzero arithmetic failures and
other operand-type diagnostics remain deferred.
