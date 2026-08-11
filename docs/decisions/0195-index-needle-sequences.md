# Decision 0195: literal index-needle sequences

`index`, `rindex`, and `indices` now accept comma-separated literal string or
numeric needles. Each needle is lowered to the existing scalar opcode and
composed through the normal comma stream, preserving output order and
ownership. Dynamic and array needles remain deferred.

Evidence: `upstream/jq/tests/jq.test:440-443` exercises two literal string
needles and the resulting ordered streams.
