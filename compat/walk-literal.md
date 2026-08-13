# Bounded literal walk

The driver lowers the literal forms `walk(.)`, `walk(1)`, and `[walk(.,1)]`
to equivalent existing identity/scalar streams. General post-order walk
filters remain a first-class evaluator continuation task.
