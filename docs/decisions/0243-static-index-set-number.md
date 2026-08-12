# Decision 0243: bounded static array-index numeric assignment

Implement root `.[INDEX] = NUMBER` with an append-only AST node and opcode. The
evaluator uses the existing transactional `array_set_take` ownership boundary,
which preserves copy-on-write behavior and jq negative-index normalization.
Nested paths, dynamic indexes, nonnumeric values, generators, and other
assignment operators remain deferred.
