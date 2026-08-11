# String multiplication compatibility shard

The bounded binary evaluator now supports string×number and number×string
repetition, including truncation, zero/negative counts, and the jq overflow
diagnostic. Dynamic generators and nonnumeric operands remain deferred.

The oracle references are `upstream/jq/tests/jq.test:1583-1603`.
