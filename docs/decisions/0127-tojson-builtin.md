# Decision 0127: bounded zero-argument `tojson`

`tojson` is represented by appended `Tojson` AST and program discriminants so
existing serialized values remain stable.  Evaluation reuses the reviewed
compact JSON serializer and allocator ownership path from `@json`.  The
inverse `fromjson` requires a parser dependency not present in the eval package
graph and remains deferred.
