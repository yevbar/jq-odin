# Decision 0215: identity reduce seed

Status: accepted (2026-08-11).

The bounded reducer evaluator recognizes an unliteralized identity node as a
seed expression and clones the current input. Literal seeds retain the existing
literal lowering path; dynamic update and binding forms remain unchanged.

Evidence: `upstream/jq/tests/jq.test:915`.
