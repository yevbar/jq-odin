# Negation diagnostic truncation

Long string values in jq's negation error are abbreviated at a UTF-8-safe
boundary before the fixed `cannot be negated` suffix. The evaluator now keeps
that diagnostic shape for ASCII and multibyte strings.

Oracle evidence: `upstream/jq/tests/jq.test:1959-1967`.
