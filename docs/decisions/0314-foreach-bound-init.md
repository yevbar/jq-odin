# Bounded foreach filter-valued initializer

Status: implemented for the jq.test:2255 scalar binding seed.

The existing foreach materializer accepts literal numeric seeds and comma
streams. jq.test:2255 additionally uses `1 as $catch | $catch - 1` as the
initializer, which evaluates to a single scalar seed before generator updates.
The evaluator now recognizes this exact Binding/Subtract shape, evaluates both
literal operands with owned values, and appends the resulting seed
transactionally. Arbitrary filter-valued initializers remain deferred to the
general resumable child-frame contract.

The focused `compat/foreach-extract.jq.test` shard covers the oracle output
`[10,19,27,34]`; existing two-clause, arithmetic-extractor, multi-seed, and
Cartesian foreach shards remain unchanged.
