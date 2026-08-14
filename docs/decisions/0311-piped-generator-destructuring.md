# Piped generator destructuring attaches to the existing pipe

For bounded array/object patterns, a producer preceded by a pipe is already
represented by the parser's `pipe_root`/`pipe_tail`. The generated Binding is
attached to `pipe_tail.right` and the original pipe root is returned, preserving
the existing Binding evaluator and program ABI. This covers jq.test cases 341
and 345 and direct piped producers.

The trim fixtures 2474/2481 remain deferred: their destructuring body is a
`try` expression containing a compound array/string-filter expression, which
still needs an independent parser continuation fix.
