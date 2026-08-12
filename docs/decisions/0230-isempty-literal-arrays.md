# Decision 0230: literal arrays for `isempty`

`isempty([literal])` is lowered through the existing `IsEmpty` opcode. Literal
arrays are values even when empty, so the result is `false`. This does not add
a continuation contract; generator and dynamic children remain deferred.
