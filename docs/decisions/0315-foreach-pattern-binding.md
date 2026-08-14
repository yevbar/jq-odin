# Decision: bounded destructuring patterns in foreach generators

The evaluator now supports the narrow jq `foreach` generator forms used by
`jq.test:341` and `jq.test:345`: one- or two-slot array patterns and simple
object `key:$variable` patterns. The parser preserves the pattern as metadata
on a synthetic `Binding` generator, so the existing four/five-operand Foreach
program ABI remains unchanged. The evaluator unwraps the producer, maps each
pattern variable to the current item, and evaluates only the bounded arithmetic
update/extract shapes covered by `compat/foreach-pattern.jq.test`.

General nested patterns, `?//` alternatives, and destructuring in `reduce` or
other generator contracts remain deferred. Missing object/array pattern fields
follow jq's null-fill behavior for the covered arithmetic forms. Invalid
patterns are rejected during syntax/compiler validation rather than entering a
partially initialized evaluator frame.
