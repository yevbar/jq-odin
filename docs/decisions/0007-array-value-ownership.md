# 0007: Array Value ownership and copy-on-write mutation

- Status: proposed
- Date: 2026-07-31
- Workstream: value

## Context and evidence

jq stores an array refcount, backing length, allocation length, and inline owned
`jv` element slots (`upstream/jq/src/jv.c:821-839`). Final backing release
destroys every stored element exactly once before freeing the array allocation
(`upstream/jq/src/jv.c:846-855`). A write reuses capacity only for an unshared
backing allocation; otherwise it allocates, retains each visible element, and
releases the old array handle. Empty arrays start with capacity 16, and a
replacement write allocates three halves of its required new visible length
(`upstream/jq/src/jv.c:813-814,867-909,990-995`). Array equality
compares equal-length elements recursively and has a same-view fast path
(`upstream/jq/src/jv.c:911-923`).

jq clamps negative and out-of-range slice endpoints. A non-empty ordinary
slice shares the consumed input backing with an adjusted view, while an empty
slice receives a fresh array (`upstream/jq/src/jv.c:925-983`). Public get
returns a retained element, and set consumes the array and incoming value,
frees an overwritten slot, fills gaps with null, and stores the incoming handle
(`upstream/jq/src/jv.c:998-1042`). The raw mutable slot reader is file-private,
while the public getter returns a retained value
(`upstream/jq/src/jv.c:867-876,1005-1015`; `upstream/jq/src/jv.h:32-47`). Set
also rejects indices above
`(INT_MAX >> 2) - jvp_array_offset(j)` before attempting a backing allocation
(`upstream/jq/src/jv.c:1018-1034`). An in-place unique write preserves the
offset, while a replacement write creates a zero-offset handle
(`upstream/jq/src/jv.c:878-909`). A nonempty slice accumulates its start in the
16-bit handle offset, but materializes and resets when that addition would
overflow (`upstream/jq/src/jv.h:30-44`, `upstream/jq/src/jv.c:961-983`). Generic
copy, release, and equality dispatch arrays through those refcounted operations
(`upstream/jq/src/jv.c:1954-2027`).

Those source rows remain proposed in the Value evidence shard, so this
decision is also proposed. Observable probes used the official jq 1.8.1 Linux
AMD64 release binary, reporting `jq-1.8.1` with SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`.
They confirm append/set and null gap filling; valid and out-of-range negative
indices; extreme positive lookup; rejected too-negative set; negative,
clamped, empty, and extreme-end slices; nested equality; and clone isolation.
The offset-relative rejection evidence is reproducible and bounded:

```sh
curl -fL -o /tmp/jq-pr28-oracle-bin \
  https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64
chmod +x /tmp/jq-pr28-oracle-bin
/tmp/jq-pr28-oracle-bin --version
sha256sum /tmp/jq-pr28-oracle-bin
timeout 3 /tmp/jq-pr28-oracle-bin -cn \
  'try (([0,1][1:] | .[536870911] = 0)) catch .'
timeout 3 /tmp/jq-pr28-oracle-bin -cn \
  'try (([0,1,2][1:][1:] | .[536870910] = 0)) catch .'
timeout 3 /tmp/jq-pr28-oracle-bin -cn \
  'try ([0] | .[536870912] = 0) catch .'
timeout 3 /tmp/jq-pr28-oracle-bin -cn \
  'try ([0] | .[-9223372036854775808] = 0) catch .'
timeout 3 /tmp/jq-pr28-oracle-bin -cn \
  'try ([range(2)][1:] | .[length] = 2 | .[536870911] = 0) catch .'
```

The first two commands print `"Array index too large"`, proving nonzero and
nested slice offsets affect the ceiling. The third prints the same diagnostic
at the base ceiling plus one; the fourth prints
`"Out of bounds negative array index"`. The fifth also prints
`"Array index too large"`: the runtime-built array has spare backing capacity,
so its consumed offset-one slice appends in place and retains the lowered
ceiling. All five exit zero because `catch` turns the diagnostic into output.
Accepted exact ceilings are not executed against jq because they would request
enormous backing allocations; bounded Odin counting-allocator tests prove the
exact accept/reject boundary without servicing the request.

The retained initialized suffix of a consumed unique slice is also observable:

```sh
/tmp/jq-pr28-oracle-bin -cn '[range(4)][1:2] | .[2]=9'
/tmp/jq-pr28-oracle-bin -cn '[range(4)][1:2] | .[3]=9'
```

The outputs are `[1,2,9]` and `[1,2,3,9]`. They follow from the fitting slice
retaining its backing and `jvp_array_write` filling only beyond the backing's
initialized length (`upstream/jq/src/jv.c:878-890,961-983`). A source-retaining
slice instead takes copy-on-write on its first mutation and copies only its
visible values (`upstream/jq/src/jv.c:891-907,1957-1961`).

Odin shallow assignment cannot implement jq's `jv_copy`. It duplicates an
owning pointer without retaining it. Odin allocator frees can also fail, so a
mutating API cannot both destroy a displaced element internally and guarantee
that every failure leaves the logical operands unchanged.

This decision composes with accepted decision 0003 rather than replacing it.
Arrays use the same opaque `Value`, clone/take/destroy vocabulary, allocator
provenance, exact-length allocation rule, and opaque owning
`Constructor_Error` contract established there. Decision 0005's retryable
final-destruction refinement applies recursively to array payloads and their
elements.

## Decision

An array is an opaque owning view handle over a shareable backing. Per-handle
state records visible length and the 16-bit jq logical/storage offset. The
backing records allocator provenance, reference count, initialized extent,
writable capacity, retirement state, and inline owned `Value` slots.
`array_value(allocator)` allocates an empty backing with jq's initial capacity
16 and returns either one complete array or an inert value plus an opaque
`Array_Operation_Error`. Array clones use the existing infallible `clone_value`
retain operation; ordinary Odin assignment of any live scalar or array
`Value` remains forbidden.

`Array_Operation_Error` exposes only `array_error_kind`,
`array_error_needs_cleanup`, `take_array_error`, and `destroy_array_error`.
Ordinary failures are inert. When exact-length validation receives a nonempty
mismatched allocation and its `Free` genuinely fails, the error takes the
owning `Constructor_Error` cleanup handle from decision 0003. A caller must
transfer or repeatedly destroy that error while its allocator remains live;
copying it is forbidden. `.Mode_Not_Implemented` retires cleanup under the
allocator's bulk lifetime, and repeated destruction is safe.

The public array operations are:

- `array_length` borrows an array for the call;
- `array_element_copy` borrows an array and returns an independently owned
  retained `Value`. The caller transfers or destroys that result exactly once.
  Raw mutable slot access is package-private and cannot escape across a growth
  or mutation boundary;
- `array_append_take` consumes the incoming element only on success and, like
  set, returns an initialized hidden-suffix owner displaced by the append (or
  invalid when the appended slot was genuinely uninitialized);
- `array_set_take` consumes the incoming element only on success and returns
  ownership of the displaced visible or initialized hidden element, or invalid
  for a genuinely uninitialized slot. The caller must transfer or destroy a
  displaced value exactly once. After negative-index normalization it reports
  `Index_Too_Large` for indices above jq's
  `(INT_MAX >> 2) - logical_offset` ceiling before any growth request, distinct
  from the `Invalid_Index` result for an out-of-bounds negative index;
- `array_slice` borrows its input and returns an independent owning handle.
  After jq endpoint clamping, a nonempty slice whose accumulated offset fits
  16 bits retains the source backing and adjusts only its view. An empty slice
  uses the explicit allocator for a fresh capacity-16 backing. Offset overflow
  uses that allocator to materialize exactly the visible length at offset zero.

Returning the displaced owner deliberately differs from jq's infallible C
API, which frees that slot inside `jv_array_set`. It preserves the same logical
set result while making Odin's fallible destruction explicit and transactional:
on every mutation error, the array and incoming element remain logically
unchanged. Passing the array handle itself as the incoming owner is rejected;
callers clone first. Because public lookup returns an owned copy rather than a
mutable interior pointer, callers cannot mutate an array-owned child in place
to construct the former outer/child reference-count cycle.

Mutation reuses a uniquely owned backing allocation when capacity suffices.
The physical write position is handle offset plus logical index. A fitting
write exposes already-initialized suffix slots and fills only genuinely
uninitialized positions with null, then extends the handle's visible length.
Such an in-place mutation preserves its offset. A shared write copies only the
handle's visible values into a new backing, fills its new logical gap with
null, and resets offset to zero; source-only prefix and suffix values remain
owned only by the old backing. A replacement backing has capacity exactly
`required_length + required_length / 2`, with checked arithmetic.

Unique growth also resets offset, but fallible recursive destruction cannot be
part of an atomic mutation. It therefore raw-transfers every old owner before
attempting the old backing `Free`: visible owners move to offset-zero slots,
while non-visible initialized owners and any earlier retirement owners move to
a private tail beyond writable capacity. That tail is never visible or
addressable by array operations and is destroyed only during final backing
retirement. This preserves jq-visible COW semantics without leaking values or
making a failed cleanup partially destroy a hidden suffix. On a genuine old
allocation `Free` failure, the old backing remains the unchanged logical owner
and the duplicate replacement is retired as raw storage. If replacement
cleanup also fails,
`Array_Operation_Error` owns that raw temporary for retry. The mutation reports
`Cleanup_Failed` without changing length, offset, capacity, elements, or the
incoming owner.

Nil/no-error, explicit allocation error, unsupported allocation, and
non-exact allocation results leave the original allocation owning and retire
or transfer any returned temporary allocation through the existing owning
error path. Exact allocation always relocates to the separate replacement.
No array growth path calls allocator `Resize`. This is required because the
pinned Odin heap allocator can free the old aligned block when its underlying
resize returns nil (`base/runtime/heap_allocator.odin:23-48,67-72,94-95`), so
neither a nil result nor an allocator error proves that the old allocation is
still live. `runtime.mem_resize` is also unsuitable as a transactional
primitive because its unsupported-mode fallback allocates, copies, and then
performs a fallible free (`base/runtime/internal.odin:196-212`).

Shared mutation first allocates a new backing through the original backing's
allocator, validates its exact length, retains visible elements, then
decrements the old backing reference. Constructor, copy-on-write, empty-slice,
and overflow-materialization allocation mismatches use the same owning error
path. Allocation failure
consumes neither operand. Element retention itself does not allocate,
so there is no partial-element-allocation failure site after backing allocation
succeeds.

Final array release walks every initialized backing slot and every private
retirement-tail owner and calls the existing fallible `destroy_value`. If a
nested final free fails after earlier elements were
successfully released, exact logical rollback is impossible. The payload
therefore enters a private cleanup-only retirement state and records the next
slot. The owning handle remains transferable and retryable through
`take_value`/`destroy_value`, but array inspection, clone, equality, and
mutation are invalid until destruction succeeds. Repeated destruction resumes
without double release. Scalar final-free failure behavior from decision 0005
is unchanged: a scalar owner remains inspectable, cloneable, and retryable.

Recursive array equality compares logical length and corresponding elements
through `values_equal`; existing invalid, null, boolean, native/literal number,
and string behavior is unchanged. Objects remain reserved and unconstructible.

## Alternatives

- Copying every slice into a unique backing was rejected because it changes
  first-write COW/reset behavior, loses initialized hidden suffix values, and
  moves the offset-relative ceiling and allocator-failure boundary.
- Deep-copying every cloned element was rejected because jq retains element
  payloads and relies on cheap sharing. It would add partial allocation sites
  without improving logical isolation.
- Destroying an overwritten element inside `array_set_take` was rejected
  because a nested allocator error can occur after earlier recursive releases;
  returning the displaced owner makes the responsibility exact.
- Exposing a dynamic array, a slice of elements, or a mutable element pointer
  was rejected because callers could retain pointers across growth, forge
  shallow owners, or construct unreclaimable outer/child cycles.
- Treating every allocator free error as success was rejected because it would
  hide leaks and contradict decision 0005.

## Consequences

This extends the accepted scalar `Value` contract without changing any scalar
constructor, accessor, clone, take, destruction, numeric comparison, string,
or equality call signature. Existing scalar callers remain source-compatible.
There is no new package or import edge.

`json` will build arrays by taking parsed elements and must destroy any
displaced owner (normally none for a newly built array append) and every
returned array-operation error. `program` and `compiler` may retain constant
arrays only through
`clone_value`; compiler imports remain within the documented graph. `eval`
must use take mutation, dispose of displaced owners, and destroy or transfer
every successful `array_element_copy` result. All of `json`, `program`,
`compiler`, and `eval` must keep captured allocator state alive through final destruction and
must propagate or deliberately handle both fallible Value cleanup and owning
array-operation errors. Adoption should follow coordinator acceptance of this
proposal. The current JSON scalar consumer needs no source change because it
does not yet call an array API: its tests still assert that arrays are
unsupported. Direct JSON ownership coverage must be sequenced with that
workstream's later array integration rather than manufactured in this Value
branch.

Object storage, iteration order, object COW, array concatenation, deletion,
iteration APIs, total ordering, and printing are intentionally deferred.

## Validation

- Allocation-tracked tests cover empty construction, shallow-alias hazards,
  clone/take/repeated destruction, unique reuse and growth, COW isolation,
  set/append/gap/negative indices, initialized hidden-suffix exposure,
  displaced ownership, shared and materialized slice boundaries, multiple
  views destroyed in both orders, nested arrays, recursive equality, and deep
  cleanup.
- Failure injection covers exact and mismatched empty construction, nonempty
  unique growth, shared COW, and empty/overflow slice materialization,
  including genuine cleanup failure, ownership transfer, retry, repeated
  destroy, and bulk retirement.
- Growth-allocation probes cover nil/no-error, short/non-exact success,
  explicit OOM with returned storage, Mode_Not_Implemented, relocation, exact
  final release, and retry after old-payload retirement failure. They also
  prove that array growth never calls allocator Resize and that each failed
  mutation preserves the array and incoming element.
- Fixed allocator thresholds prove capacity 16 needs no relocation through
  its sixteenth append, the seventeenth replacement has capacity 25, the
  twenty-sixth replacement has capacity 39, and a five-element COW result has
  capacity 7.
- Bounded upper-index probes cover integer minimum/maximum; immediately below,
  at, and above jq's base ceiling; exact boundaries for nonzero and nested
  logical offsets; 16-bit slice-offset overflow; in-place preservation; and
  growth/COW reset. Counting allocators prove every rejection precedes
  allocation and stop every accepted enormous request before backing service.
- Multi-element retirement injects a later nested release failure followed by
  a backing Free failure and proves each earlier element retires only once
  across retries. Tests also verify element retention makes no allocator call
  and therefore has no partial-element-allocation failure point.
- Allocator provenance, arena/bulk retirement, retired-detector behavior, and
  retry after nested final-free failure are covered.
- Owned-getter tests reproduce the former outer/child cycle construction
  without creating a cycle, exercise self-append through COW, and prove strict
  tracking reaches zero live allocations and no bad frees.
- Run focused tests with allocation tracking, debug checks, and debug plus
  AddressSanitizer, followed by `make validate`.
- Request independent source-aware semantic-parity, Odin ownership/safety, and
  allocation/failure-injection test-gap review lanes.
