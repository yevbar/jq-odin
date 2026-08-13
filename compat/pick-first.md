# Bounded pick(first)

The exact whole-filter `pick(first)` form is lowered to `.[0:1]`, preserving
the one-element array result through the existing slice evaluator.
