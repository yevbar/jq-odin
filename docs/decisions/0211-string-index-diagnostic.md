# Decision 0211: string numeric-index diagnostics

The string index evaluator translates numeric-index failures to the existing
owned runtime error with jq's exact semantic message, including fractional
numeric operands.
