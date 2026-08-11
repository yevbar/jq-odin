# Decision 0076: bounded `empty` builtin

`empty` is represented as a zero-argument opcode that produces no values.
The evaluator marks its frame complete immediately, allowing the standard
exhaustion continuation to advance a parent generator without allocating an
output `Value`. This preserves ownership and continuation invariants.

The syntax and program discriminants are appended to preserve existing
serialized forms. The focused evidence shard is `compat/empty.jq.test`.
