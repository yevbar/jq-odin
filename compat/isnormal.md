# `isnormal` compatibility shard

The zero-argument `isnormal` predicate emits true only for a finite, non-zero
normal numeric value. Subnormal values (`1e-320`), zero, infinities, NaN, and
non-number values emit false. The implementation follows jq's C builtin
classification (`upstream/jq/src/builtin.c:1199-1207`) and registration
(`upstream/jq/src/builtin.c:1924-1927`).

The Odin evaluator uses the IEEE-754 binary64 minimum-normal threshold
`2.2250738585072014e-308`; platform-specific libc classification is therefore
not required. Inputs whose number representation is not binary64 are outside
the current value contract.
