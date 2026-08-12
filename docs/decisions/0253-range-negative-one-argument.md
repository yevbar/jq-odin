# Decision 0253: negative one-argument range

Admit only a unary-negative numeric literal as the single `range` operand.
This reuses the existing literal range evaluator and produces jq's empty
stream for a negative upper bound. Dynamic bounds and generator-valued range
arguments remain deferred to a separate continuation contract.
