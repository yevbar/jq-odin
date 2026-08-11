# Decision 0077: bounded `values` builtin

`values` is a zero-argument filter that suppresses null input and yields a
clone of every non-null input. Null suppression marks the evaluator frame
complete and reuses normal generator exhaustion, preserving ownership and
parent continuation semantics.

The syntax and program discriminants are appended to preserve existing
serialized forms. The focused evidence shard is `compat/values.jq.test`.
