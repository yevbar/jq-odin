# Decision 0231: literal `in` and `inside`

Add append-only `In` and `Inside` syntax/opcodes for static array/object
operands. `in(xs)` evaluates membership of the current value in `xs`, while
`inside(xs)` evaluates whether `xs` contains the current value. This is a
bounded lowering; dynamic streams and generator arguments remain deferred.
