# Decision 0079: bounded `objects` builtin

`objects` is a zero-argument filter that yields a clone of object input and
suppresses all other input kinds. Suppression marks the evaluator frame
complete and reuses normal generator exhaustion, preserving ownership and
parent continuation semantics.

The syntax and program discriminants are appended to preserve existing
serialized forms. The focused evidence shard is `compat/objects.jq.test`.
