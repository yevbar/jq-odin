# Decision 0166: bounded static `isempty` generators

`isempty` now handles literal `range` children and comma streams in addition
to scalar and `empty` literals. A positive range is non-empty; a zero or
negative bound is empty. General dynamic generators and error-producing child
filters remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:2101-2105`.
