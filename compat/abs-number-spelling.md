# `abs` number spelling

For nonnegative numeric inputs, `abs` preserves the owned numeric value and
its jq-compatible decimal spelling. This avoids collapsing large integer
lexemes through an intermediate binary64 formatter.

Oracle evidence: `upstream/jq/tests/jq.test:2225`.
