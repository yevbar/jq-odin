# Decision 0219: comma-separated literal range arguments

The parser expands comma-separated numeric literals in each `range` argument
position into an ordered comma stream of ordinary range instructions. This
matches jq's Cartesian ordering while preserving the existing evaluator and
ownership contracts. Dynamic arguments and continuation forms remain deferred.
