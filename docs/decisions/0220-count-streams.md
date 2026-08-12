# Decision 0220: literal count streams

Comma-separated numeric literal counts in `limit`, `skip`, and `nth` are
expanded by the parser into an ordered comma sequence of ordinary calls. This
matches jq's stream cardinality while reusing the existing evaluator contracts.
Dynamic counts and generalized continuation forms remain deferred.
