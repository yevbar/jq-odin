# Decision 0179: zero-argument `mktime`

Add an append-only `Mktime` AST/opcode. The evaluator accepts jq datetime
arrays, converts the zero-based month to Odin's one-based month, and uses
Odin's UTC datetime conversion to produce Unix seconds. This composes with
the bounded `Strptime` implementation without changing package boundaries.
