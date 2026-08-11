# Decision 0121: dedicated `@html` AST and opcode

The parser represents the zero-argument `@html` format as a dedicated `Html`
node, and the compiler lowers it to a dedicated `Html` program opcode.  The
new enum values are appended after `Urid` so existing serialized discriminants
remain stable.  Evaluator ownership follows the established format filters:
the input is borrowed for scalar coercion, an allocator-owned escaped string is
constructed, transferred into a value, and then released on every path.

The supported semantics are jq-compatible escaping of `&`, `<`, `>`, `'`, and
`"`, with valid UTF-8 preserved.  Format arguments/interpolation, malformed
UTF-8 policy, and non-scalar containers remain explicitly deferred.
