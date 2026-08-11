# Decision 0078: bounded `arrays` builtin

`arrays` is a zero-argument filter that yields a clone of array input and
suppresses all other input kinds. Suppression marks the evaluator frame
complete and reuses normal generator exhaustion, preserving ownership and
parent continuation semantics.

The syntax and program discriminants are appended to preserve existing
serialized forms. The focused evidence shard is `compat/arrays.jq.test`.
