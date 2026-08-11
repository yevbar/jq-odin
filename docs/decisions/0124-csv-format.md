# Decision 0124: bounded scalar-array `@csv`

`@csv` is represented by appended `Csv` AST and program discriminants so
existing serialized values remain stable.  The evaluator owns an allocator-
backed builder, emits RFC4180-style quoted string fields, and releases the
transferred result.  Only scalar array fields are in scope; nested containers
and format arguments/interpolation are intentionally deferred.
