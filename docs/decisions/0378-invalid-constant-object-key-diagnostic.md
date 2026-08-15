# Invalid constant object-key diagnostic

Status: implemented bounded slice (2026-08-15)

jq.test:127 and jq.test:139 use `{(0):1}` as an object key. Pinned jq reports
`Cannot use number (0) as object key` as a compile error, with the caret on
the inner `0` (not on its grouping parentheses). The Odin parser already
retains the parenthesized key expression and the compiler already rejects
constant non-string keys before program allocation.

This slice adds `Invalid_Object_Key` to the compiler outcome and unwraps only
`Parenthesized`/`Optional` wrappers when selecting the diagnostic span. The
CLI formats the bounded constant kinds (number, boolean, null, array, and
object) using the source span. It does not change runtime object-key streams
or the separate precedence/parser diagnostic in jq.test:133 (`{1+2:3}`),
which remains deferred.

Evidence: `upstream/jq/tests/jq.test:127-142`; focused probes for
`{(0):1}` and `{non_const:., (0):1}` match pinned jq output and exit status.
