# Decision 0122: dedicated zero-argument `@text` format

`@text` is represented by appended `Text` AST and program discriminants so
existing serialized values remain stable.  The evaluator reuses the established
scalar format coercion helper and constructs an owned string result.  This
bounded slice intentionally excludes container stringification and format
arguments/interpolation; those forms need a broader formatter contract.
