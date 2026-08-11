# Decision 0173: preserve `bsearch` container diagnostics

## Scope

When the zero-argument `bsearch` family receives a non-array input, the
evaluator now serializes the input kind and compact JSON value into an owned
runtime key. This makes `try bsearch(0) catch .` match jq's diagnostic.

## Evidence

The fifth case in `compat/runtime-error-keys.jq.test` covers a string input and
the exact caught result from `upstream/jq/tests/jq.test:1801`. The combined
runtime-key shard passes 5/5 against pinned jq 1.8.1.

## Limits

Array search semantics and dynamic/multi-needle forms are unchanged. Direct
diagnostic formatting and other runtime error families remain deferred.
