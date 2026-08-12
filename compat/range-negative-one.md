# Negative one-argument range

The parser accepts the literal unary-negative operand in `range(-2)`. jq
produces an empty stream when the implicit interval `[0, -2)` is empty;
the evaluator's existing range materialization therefore emits no records.

Evidence: `upstream/jq/tests/jq.test` range cases around lines 287-303.
