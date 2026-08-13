# Literal setpath update

`setpath` now accepts a literal path array of string and integer components and
a literal replacement value. The compiler lowers both expressions as child
instructions; evaluation clones the root and recursively creates missing null
containers, preserving the input value and allocator ownership. The bounded
contract intentionally excludes dynamic path generators and `delpaths`, which
require multi-path stream/update semantics.
