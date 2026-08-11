# Decision 0140: native shortest-float normalization

The JSON compact serializer now requests fifteen significant digits for all
finite native numbers before applying jq's plain/scientific notation threshold.
This removes binary-float tail noise from native evaluator results such as
`log(2)` and `log(10)` while preserving the existing max-f64 spelling for
infinities and the literal-number decimal context. JSON owns this formatter;
the evaluator and value packages remain unchanged.

Focused regressions cover `log(2)`, `log(10)`, `log(1e20)`, and representative
ordinary, tiny-exponent, and large native values against jq 1.8.1.
