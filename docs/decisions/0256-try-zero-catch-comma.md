# Decision 0256: zero-catch try comma boundary

An implicit zero-catch `try EXP` is parsed with the comma boundary enabled.
This prevents the expression from absorbing later query outputs, so
`1, try error(2), 3` yields `1, 3` as in jq. The evaluator and ownership
contract are unchanged; explicit catches retain their existing precedence.

Evidence: `upstream/jq/tests/jq.test:1451` covers the stream shape;
`compat/try-zero-catch-comma.jq.test` adds isolated regressions.
