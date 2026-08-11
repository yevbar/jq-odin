# Decision 0125: bounded scalar-array `@tsv`

`@tsv` is represented by appended `Tsv` AST and program discriminants so
existing serialized values remain stable.  The evaluator owns a builder and
emits jq-compatible tab-separated scalar fields with explicit escapes for
backslash and control separators.  Nested containers and format
arguments/interpolation are intentionally deferred.
