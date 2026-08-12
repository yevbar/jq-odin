# Decision 0210: preserve nonnegative abs numbers

The evaluator returns a clone of a nonnegative numeric value for `abs`,
preserving its source spelling. Negative numbers continue through numeric
absolute-value computation; nonnumeric container passthrough remains intact.
