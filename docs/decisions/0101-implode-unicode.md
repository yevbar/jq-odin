# Decision 0101: Unicode codepoints for `implode` and `explode`

Extend the existing zero-argument `implode`/`explode` evaluator forms to use
UTF-8 codepoints. `implode` encodes valid scalar values, truncates positive
fractions toward zero, and substitutes U+FFFD for negatives, out-of-range
values, and UTF-16 surrogates. `explode` decodes UTF-8 sequences into codepoint
numbers. This matches the replacement-character and fractional cases at
`upstream/jq/tests/jq.test:2358-2361`.

The lane changes only evaluator behavior and retains existing value ownership;
no AST, program, or package graph contract changes are required. Malformed
UTF-8 strings and exact jq diagnostic wording remain deferred.
