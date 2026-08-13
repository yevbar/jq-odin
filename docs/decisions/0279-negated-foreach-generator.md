# Decision 0279: preserve unary negation on foreach generators

Foreach now recognizes `Negate(Field(.[]))` in its bounded array-stream path.
The change keeps existing positive foreach and Cartesian generator behavior
unchanged; arbitrary generator filters still require resumable continuations.
