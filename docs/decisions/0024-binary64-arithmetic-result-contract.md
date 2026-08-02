# 0024: Binary64 arithmetic result contract

- Status: proposed
- Date: 2026-08-02
- Workstream: value

## Context and evidence

With `USE_DECNUM`, jq distinguishes allocated decimal literal numbers from
inline native doubles. `jv_number_value` converts a literal through a reduced
17-digit decimal string and caches its binary64 value, while `jv_number`
always constructs an inline native number (`upstream/jq/src/jv.c:533-573,
601-620,674-683,699-712`). Consequently arithmetic ends literal spelling
preservation before applying the binary operation.

The numeric branches of subtraction and multiplication apply the corresponding
C double operator to the converted operands (`upstream/jq/src/builtin.c:287-292,
315-322`). Division first checks `jv_number_value(b) == 0.0`, which matches
both signs of zero, then applies C double division
(`upstream/jq/src/builtin.c:342-349`).

Despite the task brief's `fmod` premise, pinned jq 1.8.1 implements `%` by
converting the binary64 operands to saturated `intmax_t`, rejecting a divisor
that becomes zero, and applying integer `%`; it separately canonicalizes any
NaN operand and guards divisor `-1` (`upstream/jq/src/builtin.c:357-374`). The
source's `fmod` reference declares a separate libm filter, not percent-operator
semantics (`upstream/jq/src/libm.h:213-215`; operator dispatch is
`upstream/jq/src/parser.y:207-210`). Direct pinned-oracle probes confirm
`7.5 % 2.25 == 1`, `-7.5 % 2.25 == -1`, and both `1 % 0.5` and
`1 % -0.5` are runtime errors.

The pinned oracle was built from jq commit
`4467af7068b1bcd7f882defff6e7ea674c5357f4`. Language-level probes covered
ordinary signs/fractions, every literal/native pairing (using `+0` to force a
native result), signed zero via `copysign`, 2^53 boundaries, long decimals,
maximum finite values, overflow, normal/subnormal underflow, infinities, NaNs,
and modulo sign/conversion rules. Division and modulo by either zero sign each
produced empty stdout, exit status 5, and the corresponding divisor-zero
message. A filter containing 9,995 unary minuses followed by `1` exited zero
and printed `-1`.

A linked libjq probe supplied exact quiet/signaling NaN bit patterns. On this
pinned x86_64 build, subtraction and division select the left NaN when both
operands are NaNs; multiplication selects the right; each selected signaling
NaN is quieted without losing sign or payload. Modulo returns the canonical
positive quiet NaN `0x7ff8000000000000` for either NaN operand. Invalid
non-NaN operations (`infinity-infinity`, `zero*infinity`, and
`infinity/infinity`) produce `0xfff8000000000000`.

## Decision

`number_subtract`, `number_multiply`, `number_divide`, and `number_modulo`
borrow two `^Value` operands and return `(Value,
Number_Arithmetic_Result_Kind)`. The result kind is one of `Success`,
`Invalid_Operands`, or `Zero_Divisor`. Subtraction and multiplication never
return `Zero_Divisor`. Division classifies a binary64 `+0.0` or `-0.0`
divisor. Modulo classifies any divisor whose jq `intmax_t` conversion is zero,
including both zero signs and finite fractions with magnitude below one.

On `Success`, the returned Value is an independent inline native number. Every
literal/native representation pairing uses `number_value_get`, ending literal
identity exactly when jq does. NaN selection/canonicalization is explicit so
backend operand selection cannot change observable bits. Modulo implements the
pinned saturated/truncating `intmax_t` contract, including the observable
exact-`+2^63` conversion and `-1` guard; it does not use `fmod`.

These operations allocate no memory, accept no allocator, and invoke no
allocator callback. Resource failure is therefore unreachable and cannot be
confused with either a successful NaN/infinity or `Zero_Divisor`. Rejected,
successful, and classified-zero paths never mutate or consume operands.
Returned native Values have independent, infallible destruction. Existing
literal owners retain their allocator and retryable destruction contract.

## Alternatives

Returning a numeric sentinel for divisor zero was rejected because NaN and
infinity are successful observable numeric results and a future evaluator must
not infer policy from them. A boolean was rejected because it cannot distinguish
invalid operands from divisor zero. Adding an allocator/error handle was
rejected because conversion is already cached in the accepted Value
representation and result construction is inline. Implementing `fmod` was
rejected because it contradicts both pinned source and direct jq probes.

## Consequences

The future evaluator is the direct consumer: it should map `Invalid_Operands`
to its normal operator type policy and `Zero_Divisor` to jq's division or
remainder runtime message according to the opcode. It should forward `Success`
unchanged, including native NaN and infinity. No evaluator/compiler/syntax
package changes are part of this decision.

No ownership state or allocator-bearing field is added, so
`evidence/ownership/value.tsv` is unchanged. The public enum and procedures are
a shared contract; downstream consumers must switch exhaustively on the result
kind.

## Validation

Focused tests cover all four representation pairings, exact binary64 boundary
bits, operation-specific NaNs, signed zero, overflow/underflow, modulo integer
conversion/sign behavior, invalid operands, source immutability, zero-divisor
classification, allocation-free execution after an injected allocation
ceiling, and retryable literal destruction after an injected free failure.
Required review lanes are source-aware number semantics, Odin ownership/safety,
and adversarial test-gap analysis.
