# Arithmetic positive-number text compatibility shard

This shard covers jq's `tostring` behavior for positive numbers produced by
arithmetic. Internal literal spellings may carry a leading `+`, but jq omits
that sign from JSON/text output. The focused cases cover large and ordinary
positive values.

The large-value case is related to `upstream/jq/tests/jq.test:2199`.
