# Decision 0111: bounded min/max reducers

`min` and `max` are zero-argument evaluator builtins over arrays. The evaluator
retains the first candidate, compares each later value using the existing jq
ordering, and transfers ownership only when the candidate wins. Empty arrays
return `null`. `min_by`/`max_by`, dynamic generators, and expanded diagnostics
remain deferred.
