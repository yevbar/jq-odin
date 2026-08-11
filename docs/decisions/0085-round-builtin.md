# Decision 0085: bounded `round` builtin

`round` is a zero-argument numeric filter implemented with Odin's
`math.round`, returning an owned numeric value. The syntax and program
discriminants are appended to preserve existing serialized forms.

This lane covers finite numeric inputs only; non-number diagnostics and
special numeric values remain deferred. The focused evidence shard is
`compat/round.jq.test`.
