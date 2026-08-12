# Decision 0258: bounded object destructuring bindings

Direct identity object patterns with one or two static named entries are
lowered through the existing `Field` and `Binding` instructions. For example,
`. as {a:$x,b:$y} | [$x,$y]` becomes two field extractions from the identity
producer, nested in lexical binding frames. This preserves null for missing
keys and existing field error behavior for non-object inputs.

The bounded slice excludes iterator-fed, nested, dynamic-key, optional
(`?//`), and wider patterns. Those require a general pattern-matching and
alternative-selection contract.

Evidence: `upstream/jq/tests/jq.test:920-924`.
