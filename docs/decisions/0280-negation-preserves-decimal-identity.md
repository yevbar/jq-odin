# Decision 0280: preserve decimal identity under evaluator negation

Evaluator `Negate` now delegates to `value.number_negate`, which preserves
owned literal-number coefficient/exponent spelling. Native numbers retain the
existing inline path. This prevents large integer negation from rounding
before `tojson`/`tostring`.
