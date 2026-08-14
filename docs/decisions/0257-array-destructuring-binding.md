# Decision 0257: bounded array destructuring bindings

The destructuring slice supports one or two variable slots in an array pattern
over a single producer, including an iterator producer such as
`.[] as [$a, $b] | [$b, $a]`. Each slot is compiled as an ordinary lexical
binding whose producer is a static numeric index of the bound expression. This
reuses the existing evaluator continuation and variable scope machinery without
introducing a second binding representation.

The slice intentionally does not claim support for nested patterns, `?//`
alternatives, or arbitrary-width arrays. Those require a pattern-matching
contract (including input-kind failure and alternative selection) rather than
merely positional extraction.

Single-slot patterns cover rebinding cases at `upstream/jq/tests/jq.test:539-543`;
the existing two-slot evidence is at `upstream/jq/tests/jq.test:534-537`.

The generated positional index reuses the existing static `Index` ABI, whose
operand is serialized as text. Consequently, wrong-input diagnostics for a
single-slot pattern may spell the key as string `"0"` where jq reports numeric
`0`; successful bindings and ordinary two-slot behavior are unchanged. A
typed-index diagnostic repair is deferred to the shared Index ABI lane.
