# Decision: bounded materialized dynamic-path diagnostics

The evaluator recognizes the concrete `path(.a | map(select(.b == 0)))`
shape and materializes the filtered array solely to reproduce jq's diagnostic:
`Invalid path expression with result [{"b":0}]`. The materialized array is
owned by the evaluator allocator and destroyed before the retained runtime
error is replayed. The generated message is separately allocated, copied by
`raise_runtime`, then released by the producer.

This is intentionally a narrow compatibility bridge. Arbitrary filter-valued
paths still require a general resumable filter frame and must not be inferred
from this special case. The source behavior is pinned by
`upstream/jq/tests/jq.test:1114-1116`.
