# Static field filter update

This shard implements the root static update `.name |= FILTER` through a
dedicated AST/program opcode carrying the field name and RHS instruction. The
evaluator runs the RHS against the selected field value (or `null` for a
missing field/null root), commits only the first RHS output, and cancels the
remaining generator stream. An empty RHS deletes an existing object member and
leaves a null root unchanged. Errors before the first output propagate; an
error after a committed first output is not evaluated, matching jq's
path-update cardinality.

Nested paths, dynamic keys, and continuation after the update remain outside
this bounded contract. The near-match `.foo.bar |= .` remains parser-rejected.
