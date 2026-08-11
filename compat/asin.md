# `asin` compatibility shard

This shard covers the zero-argument `asin` builtin at the exact domain
endpoints and zero (`-1`, `0`, and `1`). The evaluator delegates to Odin's
`math.asin_f64`. Interior values with known libm last-digit differences,
non-number diagnostics, out-of-domain behavior, and dynamic invocation forms
remain deferred.
