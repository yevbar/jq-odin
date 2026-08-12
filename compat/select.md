# select compatibility shard

This bounded shard covers `select(predicate)` lowered through the existing
conditional/empty evaluator path. Dynamic labels, break, and assignment forms
remain outside this slice.

Oracle source: `upstream/jq/src/builtin.jq:43-44` (`select(f): if f then . else empty end`).
