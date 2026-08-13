# Decision: bounded Cartesian foreach generator

The evaluator may materialize the narrow numeric generator
`.[] / .[]` for `foreach` while the general continuation representation is
unfinished. The two `.[]` streams form a Cartesian product; jq's observable
order is right-major (`1/1, 2/1, 1/2, 2/2` for `[1,2]`). This slice computes
those values before applying the existing scalar accumulator update.

This is deliberately bounded to two array iterators and numeric division. It
does not claim support for arbitrary generator expressions, errors, or output
filters; those remain owned by the future resumable evaluator contract.
