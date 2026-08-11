# Decision 0128: scalar-only `fromjson`

`fromjson` is represented by appended `Fromjson` AST and program
discriminants.  The evaluator handles null/boolean literals directly and uses
the existing numeric literal constructor for numbers, preserving allocator
ownership.  Full JSON arrays/objects and escaped string decoding require a
future driver or a reviewed package-graph extension, so they are explicitly
out of scope.
