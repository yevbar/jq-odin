# Decision 0258: bounded object destructuring bindings

Object patterns with one or two static named entries are lowered through the
existing `Field` and `Binding` instructions. For example,
`. as {a:$x,b:$y} | [$x,$y]` and `.[] as {a:$x} | $x` become field
extractions from the producer, nested in lexical binding frames. This
preserves null for missing keys and existing field error behavior for
non-object inputs.

The bounded slice excludes nested, dynamic-key, optional (`?//`), and wider
patterns. Those require a general pattern-matching and alternative-selection
contract.

Evidence: `upstream/jq/tests/jq.test:920-924`.
