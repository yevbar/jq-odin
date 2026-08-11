# Decision 0066: bounded array `reverse`

Status: proposed on 2026-08-10.

The jq oracle's `reverse` filter reverses array order. This lane implements the
zero-argument array form as an operand-free opcode; each element is copied into
a newly owned result in descending index order. The focused evidence shard is
`compat/reverse.jq.test`.

String reversal, non-array diagnostics, and generator/assignment interactions
are intentionally deferred. No continuation or shared ownership contract is
introduced beyond the existing array append/copy APIs.
