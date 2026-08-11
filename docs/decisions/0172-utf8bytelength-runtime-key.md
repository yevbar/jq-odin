# Decision 0172: preserve `utf8bytelength` type diagnostics

## Scope

Invalid non-string inputs to zero-argument `utf8bytelength` now carry an owned
runtime key containing the input kind and compact JSON value. This allows
`try utf8bytelength catch .` to produce jq's diagnostic text.

## Evidence

The fourth case in `compat/runtime-error-keys.jq.test` covers arrays, objects,
numbers, and booleans. The combined runtime-key shard passes 4/4 against
pinned jq 1.8.1. The builtin behavior is exercised by
`upstream/jq/tests/jq.test:736`.

## Ownership and limits

The evaluator builds the diagnostic in an allocator-owned builder, `raise_runtime`
retains a copy for suppression/replay, and the temporary key is released after
raising. Direct diagnostics and unrelated runtime error families remain
deferred.
