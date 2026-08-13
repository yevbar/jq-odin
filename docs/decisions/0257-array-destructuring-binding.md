# Decision 0257: bounded array destructuring bindings

The destructuring slice supports exactly two variable slots in an array pattern
over a single producer, including an iterator producer such as
`.[] as [$a, $b] | [$b, $a]`. Each slot is compiled as an ordinary lexical
binding whose producer is a static numeric index of the bound expression. This
reuses the existing evaluator continuation and variable scope machinery without
introducing a second binding representation.

The slice intentionally does not claim support for nested patterns, `?//`
alternatives, or arbitrary-width arrays. Those require a pattern-matching
contract (including input-kind failure and alternative selection) rather than
merely positional extraction.

Evidence: `upstream/jq/tests/jq.test:534-537`.
