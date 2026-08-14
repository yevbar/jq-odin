# Decision 0283: bounded three-clause foreach extraction

The parser and compiler represent an optional `EXTRACT` clause on `foreach`
as a fourth instruction child, retaining the existing two-clause ABI when the
clause is absent. The evaluator applies the extractor after each UPDATE while
the accumulator stream is materialized, before normal iterator continuation.

This lane intentionally supports identity and identity-times-literal-number
extractors, which cover the focused upstream compatibility cases at
`upstream/jq/tests/jq.test:2255`; arbitrary generator-valued extraction remains
deferred until a general child continuation can be shared with reduce.
