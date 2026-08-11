# Decision 0065: bounded `atan` builtin

Status: proposed on 2026-08-10.

The jq 1.8.1 oracle includes a scalar precision probe
`atan * 4 * 1000000|floor / 1000000` (`upstream/jq/tests/jq.test:838`). This
lane implements only the zero-argument numeric builtin; its focused replay
shard uses the exact `atan` result for input `0` because this coordinator base
does not yet include `floor`.

`atan` is appended to the syntax and program enums to preserve existing
discriminants. The compiler lowers it to an operand-free `Opcode.Atan`; the
evaluator applies `math.atan` and reports the existing numeric misuse error for
non-number input. Argument, generator, non-finite, and diagnostic-special-case
forms are intentionally deferred.

The operation does not retain input values or introduce continuation, path, or
assignment contracts. Compatibility evidence is in `compat/atan.jq.test`.
