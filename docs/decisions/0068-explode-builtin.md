# Decision 0068: bounded ASCII `explode`

Status: proposed on 2026-08-10.

The jq `explode` filter converts a string into an array of Unicode code points.
This bounded lane handles ASCII strings by appending each byte as an owned
numeric value to a new array. The focused oracle evidence is
`compat/explode.jq.test`.

Full UTF-8 decoding and non-string diagnostics remain deferred. The opcode is
operand-free and introduces no continuation or shared ownership contract.
