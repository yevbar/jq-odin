# Decision 0177: zero-argument `trunc`

The Odin rewrite adds a dedicated append-only `Trunc` AST/opcode and lowers
the zero-argument `trunc` filter to `math.trunc`. This preserves opcode
discriminants and keeps ownership scalar-only. Non-number runtime diagnostics
remain on the existing generic path.

The focused compatibility shard is `compat/trunc.jq.test`.
