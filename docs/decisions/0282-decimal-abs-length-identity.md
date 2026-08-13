# Decision 0282: preserve decimal identity in abs and numeric length

The numeric `abs` and numeric `length` builtin paths first use the value-layer
negation operation for negative literal-backed inputs. Native values retain
the existing floating-point path; decimal overflow values no longer collapse
to the largest finite binary64 number.
