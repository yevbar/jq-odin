# 0003: Scalar Value ownership

- Status: accepted
- Date: 2026-07-30
- Workstream: integration, value

## Context and evidence

jq distinguishes invalid from JSON null
(`upstream/jq/src/jv.h:19-28`). Native numbers can live inline, while the
default decimal-number build can retain an allocated literal representation
(`upstream/jq/src/jv.c:204-210,674-683`). When both operands retain that
representation, jq compares their decimal values exactly; it falls back to
binary floating-point comparison when either operand is native
(`upstream/jq/src/jv.c:770-806`). String equality is length-aware and
byte-for-byte (`upstream/jq/src/jv.c:1265-1272`), so an embedded NUL cannot be
treated as a terminator.

Allocated jq payloads are reference counted: copying an allocated `jv`
increments its count and freeing dispatches by kind
(`upstream/jq/src/jv.c:1954-1982`). A borrowed string view does not add a
reference and must not outlive release or in-place mutation
(`upstream/jq/src/jv.c:1174-1184,1446-1449`). jq also promises to preserve a
numeric literal representation until that value is mutated
(`upstream/jq/docs/content/manual/v1.8/manual.yml:637-651`).

Odin permits shallow struct assignment and does not enforce moves, borrows, or
destructors. The package therefore needs an explicit ownership API before
other packages can safely retain runtime values.

## Decision

`value.Value` is an owning tagged handle. Its public kind space reserves
`invalid`, `null`, `boolean`, `number`, `string`, `array`, and `object`.
`invalid` is the inert zero/moved-from state and is never JSON null. The first
implementation milestone constructs only null, boolean, number, and string;
array and object payloads remain unconstructible until later decisions extend
the package.

`Value` is a union whose only payload variant is the package-private tagged
representation. The nil union is the inert invalid value. Outside packages can
hold, pass, and point to a `Value`, but cannot name or construct its variant or
select or mutate its ownership-critical kind, inline payload, or owned payload
pointer. Public constructors and ownership procedures are the only supported
way to create, inspect, transfer, clone, or retire a handle.

The scalar representation has these invariants:

- null and boolean payloads are inline;
- a native/computed number carries an inline binary `f64`;
- a JSON literal number uses an allocated payload containing its owned,
  length-delimited input spelling and the result of parsing under jq's pinned
  decNumber context (`DEC_INIT_BASE`, jq's digits adjustment, exponent bounds,
  rounding, and disabled traps at `upstream/jq/src/jv.c:508-523,576-599`);
  it may cache an `f64` conversion, but that cache is not its decimal identity;
- the decimal payload preserves the post-parse sign (including signed zero),
  coefficient digits, and exponent needed to regenerate jq's literal text.
  Decimal comparison canonicalizes zero and insignificant coefficient zeros
  without erasing representation needed for printing;
- syntactically finite inputs outside the pinned context's precision or
  exponent range round, underflow, become subnormal, or overflow exactly as
  jq's `decNumberFromString`/`decFinalize` path does
  (`upstream/jq/vendor/decNumber/decNumber.c:461-474,687-706,7310-7383`);
- a string payload owns length-delimited bytes and supports embedded NUL;
- allocated payloads retain their allocator provenance and a reference count;
- an allocator captured by a payload, and all backing state reachable through
  that allocator (including arena storage, allocator userdata, and callback
  state), must remain valid until every owning handle and clone for storage
  allocated through it has been finally destroyed;
- payload representation and reference counts are package-private;
- numeric equality is numeric, not spelling equality: two literal payloads
  compare by exact normalized decimal value, while a comparison involving a
  native number follows jq's binary `f64` fallback;
- the package's numeric comparison procedure mirrors jq's low-level
  `jvp_number_cmp` (`upstream/jq/src/jv.c:770-806`), including its native-NaN
  fallback of testing `<`, then `==`, then returning `1`; it is not a total
  Value ordering. jq's separate `jv_cmp` handles NaN before delegating numeric
  comparison (`upstream/jq/src/jv_aux.c:588-615`), and that total-value
  behavior belongs to future Value-level work;
- retaining raw input spelling is a deliberate Odin implementation choice, not
  a claim that jq's C payload keeps the original token bytes: pinned jq parses
  into `decNumber` and later regenerates text
  (`upstream/jq/src/jv.c:576-599,623-651`);
- the printing path must match jq's observable regenerated representation and
  precision; it must not assume every raw spelling is emitted byte-for-byte.
  Future arithmetic work must record which jq operations preserve a literal
  decimal payload and which produce a native number rather than applying a
  blanket conversion.

The ownership vocabulary is part of the public contract:

- `clone_value` borrows its input, returns another owning handle, and retains
  any allocated
  payload;
- `take_value(source: ^Value)` transfers the handle and writes `invalid` into
  the caller's storage;
- `destroy_value(value: ^Value)` releases one owning handle and writes
  `invalid` into the caller's storage;
- a mutable source pointer passed to take/destroy must designate one valid
  owning handle, not a shallow alias of another live handle;
- ordinary Odin `=` assignment of a live `Value` does not clone or transfer
  ownership and is forbidden across ownership boundaries;
- borrowed byte/string accessors are valid only while the source owning handle
  remains live and unmutated;
- owned data returned to a caller is allocated with an explicit caller
  allocator.

Fallible constructors return a complete owned value plus an inert constructor
error, or an inert value plus a constructor error. A constructor error is an
opaque owning handle when exact-length allocation validation received a
nonempty mismatched slice and retiring that slice genuinely failed. Callers
inspect it with `constructor_error_kind`, transfer it with
`take_constructor_error`, and retry `destroy_constructor_error` while keeping
the captured allocator and its backing state alive. Ordinary syntax, overflow,
nil/no-error, allocator-error, and successfully retired mismatch failures carry
no storage. Constructor errors must not be copied.

Every allocation boundary requires an exact-length result before indexing or
constructing a payload. A nil/no-error or short/no-error result is an allocation
failure. Any nonempty mismatch is retired with its originating allocator;
`.Mode_Not_Implemented` is successful retirement under the allocator's bulk
lifetime, while a genuine `Free` failure keeps the only slice handle in the
constructor error for retry. Thus constructors release or transfer every
partial allocation on failure rather than losing it.

Destruction uses the allocator captured by the payload, never whichever
allocator is current in the caller's Odin `context`. Arena-backed values and
their clones must therefore be destroyed before arena teardown. A future
explicit bulk-retirement operation may replace individual destruction only if
its contract says that it releases or retires all affected payload storage,
invalidates every affected handle, and makes every operation permitted after
that point allocator-free. Without such a documented operation,
`destroy_value` is the retirement point, and the allocator backing state may
be torn down only after the last owning handle has been destroyed.

## Alternatives

- **Treat Odin assignment as a value copy.** Rejected because it duplicates an
  owning pointer without retaining it.
- **Deep-copy every value.** Rejected because jq relies heavily on cheap
  sharing and copy-on-write; it would also obscure the ownership facts being
  translated.
- **Use nil as JSON null.** Rejected because jq distinguishes invalid from
  null and because a moved-from/error sentinel must not become observable
  JSON.
- **Store strings as `cstring`.** Rejected because jq strings are
  length-delimited and may contain embedded NUL.
- **Use `f64` as every number's identity while retaining literal text only for
  printing.** Rejected because distinct decimals beyond binary precision can
  collapse to the same `f64`, while jq compares two retained literals as exact
  decimals.
- **Require an external decimal runtime for the scalar milestone.** Rejected
  as a requirement: literal comparison and rendering can be implemented from
  the bounded parsed sign, coefficient, exponent, and status. A narrow
  transitional binding remains allowed if it is proven behavior-equivalent
  and does not leak into the public API. Later decimal arithmetic may revisit
  the dependency choice.
- **Choose array/object layout now.** Rejected until their copy-on-write,
  ordering, view, and failure contracts receive focused implementation
  decisions.

## Consequences

`json`, `program`, and `eval` may retain a `Value` only by receiving ownership
or calling `clone_value`. Their APIs must name borrowed versus owned
parameters and results. Direct constructor consumers must also inspect and
retire or transfer every returned constructor error before allocator teardown.
At this refinement's adoption, the direct consumers are `json.parse_scalar`
and the focused Value tests; future `program` and `eval` consumers inherit the
same rule. They use the public procedures rather than selecting representation
fields. Syntax remains independent of `Value`. The opaque union layout changes
no package import edge.

The scalar implementation must not expose fields that let another package
forge a kind/payload mismatch. Exhaustive switches must handle the reserved
array/object kinds even though constructors are not yet available.

## Validation

- Allocation-tracked tests for clone, take, destroy, constructor failure,
  exact-length nil/short results, retryable mismatch cleanup, and allocator
  provenance.
- A retired/detector allocator test proves that allocator backing state stays
  valid through final destruction (or a documented bulk-retirement operation)
  and that no operation permitted afterward calls the allocator.
- A clone remains valid after its source is destroyed.
- A taken-from value is invalid and owns nothing.
- String round trips preserve embedded NUL and byte length.
- `1`, `1.0`, and `1.00` retain their input spelling internally, compare
  numerically equal, and print exactly as the pinned jq oracle does.
- `9007199254740992` and `9007199254740993` compare unequal while both remain
  literal values, even if their cached `f64` conversions collide.
- Signed-zero, leading/trailing-zero, exponent-spelling, maximum/minimum
  exponent, subnormal, underflow, overflow, and precision-boundary cases match
  the pinned jq oracle for comparison and printing.
- Focused mixed literal/native comparisons match jq's `f64` fallback.
- Debug and ASan package tests, followed by `make validate`.
- Independent Odin ownership/safety and jq semantic-parity review lanes.
