# Decision 0166: bounded `acosh` builtin

Add jq's zero-argument `acosh` numeric filter as an append-only AST/opcode
extension, preserving existing serialized discriminants. Numeric inputs use
Odin `math.acosh_f64`; non-numeric inputs retain the existing numeric-error
class. Focused compatibility coverage includes `1`, `2`, and the
out-of-domain value `0`. Dynamic forms and platform-sensitive last-digit
differences remain outside this bounded slice.
