# Decision 0067: bounded ASCII `implode`

Status: proposed on 2026-08-10.

The jq `implode` filter converts an array of Unicode code points to a string.
This bounded lane handles integral values in the ASCII range 0..127, using an
operand-free opcode and an owned strings builder. The focused oracle evidence
is `compat/implode.jq.test`.

Full Unicode encoding, non-array diagnostics, and malformed code-point
behavior remain deferred; no continuation or shared ownership contract is
introduced.
