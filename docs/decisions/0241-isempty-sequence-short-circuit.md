# Decision 0241: short-circuit static `isempty` sequences

The bounded evaluator inspects static sequence children: a non-`empty` left
child proves that the sequence has output, so `isempty` returns `false` without
running a later branch. If both children are explicit `empty`, it returns
`true`. Dynamic sequences and generator/error interactions remain deferred.
