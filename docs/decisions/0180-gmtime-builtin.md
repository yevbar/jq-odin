# Decision 0180: zero-argument `gmtime`

Add an append-only `Gmtime` AST/opcode. The evaluator converts numeric Unix
seconds with Odin's UTC time package and emits jq's eight-element datetime
array (zero-based month and day-of-year, Sunday-based weekday).
