# Decision 0089: bounded `ceil` builtin

Add `ceil` as an operand-free numeric builtin. Its evaluator uses Odin's
`math.ceil` on the binary64 value and preserves jq's numeric type error for
non-number inputs. The AST and opcode discriminants are appended after the
current builtin forms, so existing serialized programs retain their values.
