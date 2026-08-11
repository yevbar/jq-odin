# Decision 0122: dedicated zero-argument `@text` format

`@text` is represented by appended `Text` AST and program discriminants so
existing serialized values remain stable.  The evaluator renders all JSON
value kinds as compact JSON into an allocator-owned string, preserving nested
array/object structure and insertion order.  Format arguments/interpolation
remain excluded; those forms need a broader formatter contract.
