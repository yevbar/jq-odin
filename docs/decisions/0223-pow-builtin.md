# Decision 0223: bounded `pow(base; exponent)` builtin

Add an append-only `Pow` AST/opcode with two child filters. The evaluator uses
the existing numeric value contract and Odin's `math.pow_f64`; non-numeric
diagnostics and dynamic continuation-heavy forms remain outside this slice.

Oracle evidence is isolated in `compat/pow.jq.test`. The upstream jq cases
using this builtin are `upstream/jq/tests/jq.test:2025-2029`.
