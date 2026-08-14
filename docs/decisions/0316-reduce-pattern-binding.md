# Decision: bounded destructuring patterns in reduce generators

The evaluator supports the two selected `reduce` destructuring forms at
`jq.test:894` and `jq.test:898`: two-slot array patterns and one nested simple
object field. The parser preserves the pattern as metadata on the synthetic
`Binding` generator, and the existing four-operand Reduce ABI remains intact.
The bounded evaluator materializes either a `.[]` array producer or a literal
array producer and evaluates identity, variable, literal, and arithmetic update
nodes through the existing value kernel.

Nested/general patterns, `?//` alternatives, generator-valued updates, and
reduce forms requiring arbitrary child continuations remain deferred. Invalid
patterns fail compiler validation before evaluator frame setup.
