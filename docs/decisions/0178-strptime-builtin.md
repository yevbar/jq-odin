# Decision 0178: bounded ISO `strptime`

Add an append-only `Strptime` AST/opcode. The evaluator uses Odin's ISO-8601
component parser for two literal formats and constructs jq-compatible
`[year, month-1, day, hour, minute, second, weekday, day-of-year-1]` arrays.
This keeps the datetime conversion owned by the evaluator and does not alter
existing opcodes or package boundaries.
