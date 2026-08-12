# Decision 0204: bounded numeric slice reads

Implement read-only numeric array and UTF-8 string slices as a postfix opcode.
Bounds are literal integers with jq's negative-index normalization and
omitted-bound defaults; string bounds use code-point indexes. Array results
own fresh storage and string results own fresh text. Assignment, deletion, and
dynamic bounds remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:466-472`. Focused array regression
coverage also lives in `compat/negative-index.jq.test`.
