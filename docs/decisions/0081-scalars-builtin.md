# Decision 0081: bounded `scalars` builtin

`scalars` is a zero-argument filter that yields a clone of null, boolean,
number, or string input and suppresses arrays and objects. Suppression marks
the evaluator frame complete and reuses normal generator exhaustion,
preserving ownership and parent continuation semantics.

The syntax and program discriminants are appended to preserve existing
serialized forms. The focused evidence shard is `compat/scalars.jq.test`.
