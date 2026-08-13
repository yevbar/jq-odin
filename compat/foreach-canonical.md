# Canonical foreach compatibility shard

This shard covers the bounded canonical forms `foreach .[] as $x (0; . +
$x)` and `foreach range(5) as $x (0; $x)`. The evaluator materializes the
updated accumulator stream while preserving one output per update. General
generator continuations, nested bindings, and arbitrary update filters remain
follow-up work.
