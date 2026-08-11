# Decision 0171: preserve `toboolean` parse diagnostics through catches

## Scope

Invalid scalar and container inputs to zero-argument `toboolean` now carry a
serialized, owned runtime key in the evaluator. The key includes the jq value
kind and compact JSON value, so `try toboolean catch .` returns jq's diagnostic
text rather than an empty string.

## Evidence

The third case in `compat/runtime-error-keys.jq.test` covers null, number,
invalid string, array, and object inputs. The shard passes 3/3 against pinned
jq 1.8.1. The source builtin is defined as a type conversion in
`upstream/jq/src/builtin.jq:72-76`.

## Ownership and limits

The evaluator builds a temporary owned key, `raise_runtime` copies it into the
runtime-error owner, and the temporary allocation is released immediately.
Dynamic error formatting for other builtins remains deferred.
