# Decision 0262: bounded dynamic path generator

The path evaluator now recognizes a static path followed by jq's empty postfix
iterator (`path(.foo[])`). The parser already represents `[]` as an empty-name
`Field`; the evaluator validates the surrounding chain, resolves the static
prefix once, and materializes immediate child paths in `paths_results`. The
existing resumable path stream phase emits each result independently.

This deliberately does not accept arbitrary filters as path expressions. Such
filters require a general path/continuation contract and must not be simulated
by textual expansion. Null, scalar, and missing-prefix iteration errors remain
runtime behavior and are covered by the broader CLI contract.
