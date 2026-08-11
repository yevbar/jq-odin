# Decision 0181: ISO date aliases

The parser maps `fromdateiso8601` and `fromdate` to the append-only
`Fromdate` opcode, and `todateiso8601` and `todate` to `Todate`. Their
evaluator paths reuse the reviewed `strptime`, `mktime`, `gmtime`, and
`strftime` implementations, avoiding duplicate date conversion logic.
