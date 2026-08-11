# Decision 0100: parsed scalar coercion for literal `join`

The evaluator's existing literal-separator `Join` form now accepts parsed
number and boolean members in addition to strings and null. Parsed number
literal spelling is borrowed from the owned value payload, preserving jq's
ordinary source spelling (for example, `3.4` rather than a binary-float
expansion); exponent notation is canonicalized to jq's uppercase `E` form with
an explicit sign.
Null remains an empty member and separators are emitted exactly as before.

This is intentionally an evaluator-only extension: no AST, opcode, program,
or package-boundary contract changes are needed. Arrays and objects continue
to report the existing iteration error; dynamic or generator separators and
native numbers produced by arithmetic remain deferred to a future serializer
contract. The compatibility target is the scalar join cluster at
`upstream/jq/tests/jq.test:1976-1996`.
