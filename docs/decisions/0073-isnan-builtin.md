# Decision 0073: bounded `isnan` builtin

Status: proposed on 2026-08-11.

`isnan` emits a boolean indicating whether its numeric input is NaN. This
operand-free lane uses Odin's `math.is_nan`; non-number diagnostics remain
deferred. Focused oracle evidence is `compat/isnan.jq.test`.
