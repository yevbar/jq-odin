# Materialized dynamic path result

This shard covers jq's invalid-path diagnostic when a filter materializes an
array of objects. The evaluator preserves the materialized value in the error
message while keeping the result owned by the evaluator until diagnostic
retention completes.

The fixture is derived from `upstream/jq/tests/jq.test:1114-1116`.
