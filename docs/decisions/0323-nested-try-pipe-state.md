# Parenthesized try stages in a pipe

When a parenthesized `try` expression is the right operand of an existing
pipe, the parser must delimit the try expression at the enclosing close
parenthesis rather than carrying the outer pipe state through its catch
subparser. Otherwise the parser leaves the preceding pipe tail open and the
compiler correctly rejects the AST as invalid. The fix is parser-state only;
the existing Try/Sequence evaluator ABI is reused. Bare `error` now also
retains a string input as its runtime key so an uncaught string error reports
the same value as jq.

Evidence: `compat/nested-try-streams.jq.test` matches the pinned jq oracle for
the three selected stream/catch cases; ordinary try/catch and pipe forms
remain covered by package tests.
