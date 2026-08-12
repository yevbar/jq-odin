# Decision 0206: fractional array indices

Numeric array indices are converted to their integer truncation before
negative-index adjustment and lookup, matching jq. Fractional string indexing
continues to produce the existing typed runtime error.
