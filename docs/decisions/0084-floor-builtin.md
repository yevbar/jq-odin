# Decision 0084: bounded `floor` builtin

`floor` is a zero-argument numeric filter implemented with Odin's
`math.floor`, returning an owned numeric value. The syntax and program
discriminants are appended to preserve existing serialized forms.

This lane covers finite numeric inputs only; non-number diagnostics and
special numeric values remain deferred. The focused evidence shard is
`compat/floor.jq.test`.
