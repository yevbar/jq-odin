# Decision 0123: dedicated zero-argument `@json` format

`@json` is represented by appended `Json` AST and program discriminants so
existing serialized values remain stable.  The evaluator reuses the reviewed
recursive compact JSON serializer from the `@text` lane, preserving string
escaping, nested arrays/objects, and object insertion order.  Format
arguments/interpolation are intentionally deferred.  Literal exponent
notation is normalized to jq's uppercase `E` spelling with a positive sign
where required.
