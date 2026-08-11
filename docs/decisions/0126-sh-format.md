# Decision 0126: bounded scalar-array `@sh`

`@sh` is represented by appended `Sh` AST and program discriminants so
existing serialized values remain stable.  The evaluator owns an allocator-
backed builder and emits POSIX single-quoted string fields separated by spaces;
embedded apostrophes are escaped as `\\''`.  Nested containers and format
arguments/interpolation are intentionally deferred.
