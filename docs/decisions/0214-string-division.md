# Decision 0214: string division delegates to split

Status: accepted (2026-08-11).

When both operands of `/` are strings, jq splits the left string on the right
separator. The evaluator reuses the existing owned `split_result` helper;
numeric division remains unchanged.

Evidence: `upstream/jq/tests/jq.test:1607-1611`.
