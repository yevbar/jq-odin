# 0019: Number negation ownership

- Status: proposed
- Date: 2026-08-02
- Workstream: value

## Context and evidence

With decimal-number support, jq negates a literal by allocating a new literal
payload with a null generated-spelling pointer and applying `decNumberMinus`;
it does not copy the source payload's lazily generated spelling
(`upstream/jq/src/jv.c:561-573,755-767`). It negates a native number with unary
binary64 minus (`upstream/jq/src/jv.c:755-767`). The unary-negation builtin
rejects non-numbers and releases its consumed input only after the negated
result is constructed (`upstream/jq/src/builtin.c:243-249`). Compact printing
uses a retained decimal literal when available, maps NaN to `null`, and clamps
infinities before native formatting (`upstream/jq/src/jv_print.c:253-277`).
The first request for a fresh finite literal generates its bytes with
`decNumberToString` without trimming decimal precision
(`upstream/jq/src/jv.c:623-651`). Its exact plain/scientific choice, uppercase
`E`, signed exponent, and coefficient sign rules are defined at
`upstream/jq/vendor/decNumber/decNumber.c:3606-3766`. `decNumberMinus` computes
`0 - operand`, rather than performing a quiet sign-bit copy
(`upstream/jq/vendor/decNumber/decNumber.c:1615-1645`). Its exact-zero add path
clears the result sign except for round-toward-negative-infinity; jq's decimal
context uses the `DEC_INIT_BASE` half-up default, so literal zero negation is
always positive zero (`upstream/jq/src/jv.c:508-523`;
`upstream/jq/vendor/decNumber/decContext.c:72-87`;
`upstream/jq/vendor/decNumber/decNumber.c:3883-3889,4125-4135`).

The oracle was built from the pinned jq commit
`4467af7068b1bcd7f882defff6e7ea674c5357f4` and bundled Oniguruma commit
`4ef89209a239c1aea328cf13c05a2807e5c146d1` with:

```sh
oracle=$(tools/compat/build-oracle.sh)
"$oracle" --version
```

The version output was exactly `jq-1.8.1`. Literal compilation and nested
negation were probed with the following command shape (once for every literal
listed below):

```sh
"$oracle" -cn '[LITERAL,-(LITERAL),-(-(LITERAL))]'
```

Exact compact outputs were:

```text
1e+00       [1,-1,1]
1E+00       [1,-1,1]
1.2300e+4   [12300,-12300,12300]
1.2300      [1.2300,-1.2300,1.2300]
123.00      [123.00,-123.00,123.00]
01          [1,-1,1]
00.0100     [0.0100,-0.0100,0.0100]
000e+2      [0E+2,0E+2,0E+2]
0           [0,0,0]
9007199254740993 [9007199254740993,-9007199254740993,9007199254740993]
123456789012345678901234567890.00 [123456789012345678901234567890.00,-123456789012345678901234567890.00,123456789012345678901234567890.00]
1e999999999 [1E+999999999,-1E+999999999,1E+999999999]
1E+999999999 [1E+999999999,-1E+999999999,1E+999999999]
1e-1147483646 [1E-1147483646,-1E-1147483646,1E-1147483646]
4e-1147483647 [0E-1147483646,0E-1147483646,0E-1147483646]
1e1000000000 [1.7976931348623157e+308,-1.7976931348623157e+308,1.7976931348623157e+308]
```

The exact positive- and negative-zero input probe was:

```sh
for input in 0 -0 0.00 -0.00 0e+2 -0e+2 0e-2000000000 -0e-2000000000; do
  printf '%s\n' "$input" | "$oracle" -c '[.,-.,--.]'
done
```

Its output was:

```text
[0,0,0]
[-0,0,0]
[0.00,0.00,0.00]
[-0.00,0.00,0.00]
[0E+2,0E+2,0E+2]
[-0E+2,0E+2,0E+2]
[0E-1147483646,0E-1147483646,0E-1147483646]
[-0E-1147483646,0E-1147483646,0E-1147483646]
```

Additional source-built probes covered multiple integer, fraction, exponent,
negative, underflowed, and repeatedly negated zero forms:

```sh
for input in 0 -0 0.00 -0.00 000e+2 -000e+2 0.000 -0.000 \
             0e-20 -0e-20 4e-1147483647 -4e-1147483647; do
  printf '%s\n' "$input" | "$oracle" -c '[.,-.,--.]'
done
```

The exact outputs were:

```text
[0,0,0]
[-0,0,0]
[0.00,0.00,0.00]
[-0.00,0.00,0.00]
[0E+2,0E+2,0E+2]
[-0E+2,0E+2,0E+2]
[0.000,0.000,0.000]
[-0.000,0.000,0.000]
[0E-20,0E-20,0E-20]
[-0E-20,0E-20,0E-20]
[0E-1147483646,0E-1147483646,0E-1147483646]
[-0E-1147483646,0E-1147483646,0E-1147483646]
```

Where the host exposes `copysign`, jq registers it as a two-number math
builtin (`upstream/jq/src/builtin.c:154-169` and
`upstream/jq/src/libm.h:157-161`). The observable binary64-sign probe was:

```sh
for input in 0 -0 0.00 -0.00 000e+2 -000e+2 \
             0e-20 -0e-20 4e-1147483647 -4e-1147483647; do
  printf '%s\n' "$input" |
    "$oracle" -c '[copysign(1;.),copysign(1;-.),copysign(1;--.)]'
done
```

Every positive source produced `[1,1,1]`; every negative source produced
`[-1,1,1]`. Thus the input sign remains observable, while the first and every
repeated literal negation expose positive zero.

Leading `+` is permitted in the exponent by the lexer but not before a jq
filter literal (`upstream/jq/src/lexer.l:95-96`). Rejection probes were:

```sh
"$oracle" -cn '+1'
"$oracle" -cn '+01'
"$oracle" -cn '01.2.3'
"$oracle" -cn '00e+'
"$oracle" -cn '1e+'
```

Every command exited 3. Their exact first diagnostic lines were, respectively,
`syntax error, unexpected '+'`, `syntax error, unexpected '+'`, `syntax error,
unexpected LITERAL`, `syntax error, unexpected IDENT`, and `syntax error,
unexpected IDENT`; each ended with `jq: 1 compile error`.

## Decision

`number_negate(source: ^Value, allocator: runtime.Allocator)` borrows `source`
for the complete call and returns `(Value, Constructor_Error, bool)`. Nil,
invalid, and non-number sources return an inert Value, inert constructor error,
and `false` without allocation. This follows the existing Value accessor style
for a non-owning kind mismatch. They do not change the source. Allocation
failure also returns `false` and is distinguished by the Constructor_Error.

Native numbers return a separate inline native Value without allocation. The
operation toggles bit 63 of the stored binary64 value. This preserves every
other bit, including NaN payload bits, and toggles signed zero, infinities,
and NaN signs exactly.

Literal numbers return a distinct payload allocated with the caller allocator.
The implementation performs one exact-size payload allocation and no temporary
owned allocation. It copies the normalized coefficient, exponent, infinity
state, and cached binary64 bits while applying the existing decimal/cache sign
transition. It deliberately clears `explicit_positive_sign`. Before allocating,
it calculates the exact `decNumberToString` byte count from the normalized
coefficient and exponent; after the one allocation it writes that canonical
spelling directly into the destination. Decimal zero spelling is unsigned, its
stored decimal sign is clear, and its cached binary64 is positive zero,
matching fresh `decNumberMinus`. Double and repeated zero negation regenerate
the same canonical positive form and state rather than toggling a hidden sign
or recovering any source lexeme. This zero-canonicalization rule is specific
to literal-backed decimal negation; native f64 negation retains the ordinary
IEEE sign toggle. No source spelling, storage, or style bit is retained or
transferred.

Allocation uses the existing Constructor_Error contract. Explicit allocator
errors, nil success, and short success fail with an inert result. A nonempty
mismatch is retired; genuine Free failure transfers its allocation into the
owning cleanup state, while `Mode_Not_Implemented` is successful bulk
retirement. Successful results use the existing retryable `destroy_value`
contract. Source and result destroy independently in either order, and every
successful double negation creates independent owners.

## Alternatives

- Clone-then-mutate was rejected because it would share the source payload and
  require a second allocation before independent mutation.
- Converting through binary64 was rejected because it loses decimal identity,
  precision, and generated decimal spelling.
- Moving or mutating the source was rejected because evaluation needs a
  borrowed operation and independent output lifetime.

## Consequences

The public Value contract gains `number_negate` without changing the shared
Error kind space, package graph, or import edges. Current affected consumers
are `json`, `program`, `compiler`, and `eval`; they require no change in this
slice.
Future evaluator unary-negation code must pass an explicit allocator, preserve
the source owner through the call, and retire either the returned Value or an
owning Constructor_Error cleanup state.

`json.serialize_compact` is a direct behavioral consumer but cannot be imported
by `value` tests because `json` already imports `value`. Cross-package compact
coverage must therefore remain in the json or compatibility lane after this
Value API is available; the Value branch does not add a reverse import edge.

## Validation

Focused allocation-tracked tests cover rejection, native bit patterns,
literal metadata and exact canonical bytes for every oracle family above,
independent destruction orders, double negation, exact one-allocation sizing,
allocation failures, cleanup transfer and retry, bulk retirement, and final
result destruction retry. Value tests run with one and four threads in default,
debug, optimized, assertions-disabled, and AddressSanitizer/LeakSanitizer
configurations, followed by `make validate`.

Required review lanes are source-aware semantic parity, Odin ownership and
resource safety, and allocation/failure test-gap falsification.
