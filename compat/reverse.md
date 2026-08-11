# `reverse` compatibility shard

This lane covers zero-argument `reverse` for arrays. The evaluator allocates a
new array and appends owned element copies in reverse order, preserving source
ownership. String reversal, non-array diagnostics, and nested generator forms
remain deferred.
