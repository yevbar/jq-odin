# Static slice assignment

Status: implemented in the CLI vertical slice (2026-08-13)

The implementation adds a dedicated `Static_Slice_Set_Number` syntax/program
opcode carrying two numeric bounds and the source-level RHS. The evaluator
parses the bounded literal RHS, clones the untouched array prefix/suffix, and
splices the RHS array. String input raises the exact jq runtime error. This is
intentionally bounded to static numeric bounds and literal RHS values; dynamic
RHS generators remain a future continuation contract.

Null input is coerced to an empty array, while scalar/object inputs preserve
jq's catchable `Cannot index ... with object` diagnostics. NaN and infinite
bounds are normalized to jq's edge semantics before native integer conversion.

Focused probes match jq for both pinned cases. `make validate` is required
before integration.
