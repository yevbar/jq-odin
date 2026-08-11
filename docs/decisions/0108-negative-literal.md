# Decision 0108: lower unary numeric literals

The compiler lowers `-NUMBER` directly to an owned negative numeric literal,
preserving the existing evaluator and program contracts. This enables root and
constructor literals from `upstream/jq/tests/jq.test:25,39` without claiming
support for dynamic unary negation (`-.`) or richer control-flow compositions.
