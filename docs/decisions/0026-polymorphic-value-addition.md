# 0026: Polymorphic Value addition ownership and failure contract

- Status: proposed
- Date: 2026-08-03
- Workstream: value

## Context and evidence

Pinned jq 1.8.1 dispatches `+` in this order: left null returns the consumed
right value, right null returns the consumed left value, two numbers are
converted with `jv_number_value` and added as C doubles into a fresh inline
`jv_number`, two strings call `jv_string_concat`, two arrays call
`jv_array_concat`, and two objects call `jv_object_merge`; all other pairs
produce `cannot be added` (`upstream/jq/src/builtin.c:82-103`). There is no
`jv_number_add` procedure in the pinned tree: the number addition operation is
spelled directly at `upstream/jq/src/builtin.c:89-94`. Decision 0021 and its
`number_add` primitive already pin the resulting binary64, NaN-selection, and
signed-zero behavior.

String concatenation appends the right bytes to the consumed left string and
then releases the right (`upstream/jq/src/jv.c:1500-1504`). Array concatenation
iterates the right array in index order, appends each retained element to the
consumed left array, and then releases the right (`upstream/jq/src/jv.c:1045-1055`).
Object merge iterates the right object and sets every retained key/value into
the consumed left object before releasing the right
(`upstream/jq/src/jv.c:1884-1891`). New object keys use successive free slots,
duplicate updates retain the old slot, rehash transports occupied slots in old
slot order, and iteration scans increasing slot indices while skipping holes
(`upstream/jq/src/jv.c:1650-1660,1685-1705,1734-1759,1924-1952`). Therefore a
shallow merge preserves all left keys in their existing order, replaces a
duplicate value without moving its key, and appends right-only keys in right
iteration order.

The exact oracle was the official jq 1.8.1 Linux AMD64 release binary from
`https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-amd64`.
It reported `jq-1.8.1` and SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`,
the provenance already used by decisions 0007 and 0010. The local source
submodule was independently verified at jq commit
`4467af7068b1bcd7f882defff6e7ea674c5357f4` with bundled Oniguruma commit
`4ef89209a239c1aea328cf13c05a2807e5c146d1`.

Direct compact probes covered null on both sides of every live kind, every
accepted same-kind pair, invalid mixed pairs, duplicate and reinserted object
keys, nested arrays/objects, NaN, infinities, and signed zero. The key-order
probe

```sh
/tmp/jq-add-oracle-1.8.1 -cn \
  '[({a:1,b:2}+{a:3}),(({a:1,b:2}+{a:3})|keys_unsorted),
    (({a:1,b:2}+{b:3,c:4})|keys_unsorted),
    (({a:1,b:2,c:3}|del(.b)|.d=4)+{b:5,a:6,e:7}|keys_unsorted),
    (({a:1}+{b:2,a:3,c:4})|keys_unsorted)]'
```

printed exactly
`[{"a":3,"b":2},["a","b"],["a","b","c"],["a","c","d","b","e"],["a","b","c"]]`.
The numeric edge probe printed `null` for NaN results, clamped both infinity
signs at output, and observed positive signs for `-0+-0`, `-0+0`, and `0+-0`
through `copysign`; decision 0021's linked-library evidence separately pins
the internal negative-zero result of native `-0 + -0` before jq filter-literal
negation canonicalization affects a source-level expression.

## Decision

`value_add(left, right: ^Value, allocator: runtime.Allocator)` borrows both
operands for the complete call and returns `(Value, Value_Add_Error)`. It
never consumes, mutates, retains, or releases either input. The pointers may
be identical and the operands may share any payload. A successful result is a
complete independent owner; it shares no allocated payload with either source
or with any nested source value and may be destroyed before or after either
operand.

The accepted table is exact:

| Left | Right | Result |
|---|---|---|
| null | any live Value | independent deep copy of right |
| any live Value | null | independent deep copy of left |
| number | number | existing allocation-free `number_add` result |
| string | string | left bytes followed by right bytes |
| array | array | left elements followed by right elements |
| object | object | top-level shallow merge, right value wins |

`null + null` returns null. Boolean plus boolean and every other live type pair
return `Invalid_Type_Pair`. Nil/inert handles, cleanup-only containers, and
representation-inconsistent internal Values return `Invalid_Operand`.

Both complete reachable representations are validated before null identity or
type-pair dispatch and before the result allocator is called. Validation checks
scalar payload kind, reference and exact allocation metadata; Array
slice/count/capacity/retired-owner bounds and every owned initialized or retired
slot; and Object capacity, live-slot counts, every key and value, key/hash
metadata, bucket chains, unique textual keys, and exact allocation size. A
corrupted descendant is an invalid operand regardless of the other root kind;
a corrupted internal length is an invalid operand, not a requested result-size
overflow.

Every empty Object slot has one canonical representation: `next == -1`, a zero
hash, and inert `key` and `value` handles. This applies to erased holes below
`object_next_free` and unused capacity at or above it. Preflight checks the
complete slot extent after independently proving its physical allocation bound;
an Invalid/inert key does not hide a live value or noncanonical hash/link state.
Object allocation, deletion, COW copying, rehash, and addition construction
create or preserve this representation. Final malformed-object retirement
examines the key and value positions independently through bounded slot-order
cursors, so a missing key cannot suppress retirement of a safely discoverable
value owner and a failed retirement remains retryable without double release.

Every owning `Value` also records the exact allocator-returned extent for its
payload independently of mutable payload metadata. Constructors install the
payload and extent together; clone, take, and Array slicing preserve both;
copy-on-write replacement changes both in one transaction; and inline or inert
handles retain a zero extent. Kind-specific arithmetic and the independent
extent are checked before forming any variable-length String, literal-number,
Array, or Object view. Final retirement uses the handle extent rather than the
payload's size field.

Preflight is an iterative depth-first walk. Exact-size linked scratch blocks
come from `runtime.heap_allocator()`, not the allocator supplied to `value_add`,
and are retired before dispatch. Stable per-payload visiting/completed records
reject ownership cycles, permit shared acyclic payloads, and prevent repeated
subgraphs from expanding without bound; borrowed Values and payloads are never
used as traversal scratch. A completed payload reached through another owning
handle is a legitimate shared DAG/COW edge, not a cycle: validation skips its
already checked descendants without changing its reference count or value.
Each scratch block holds at most 32 active frames and 32 stable seen records;
the linked block count is bounded by the number of traversal frames plus unique
container payloads and is independent of procedure-call stack depth.

Scratch allocation failure maps to `Out_Of_Memory` or
`Allocator_Unsupported`. A short allocation is retired immediately, and a
genuine scratch retirement failure transfers the exact remaining block cursor
to `Value_Add_Error`, reports `Cleanup_Failed`, and is retryable through
`destroy_value_add_error`. "Zero result-allocation work" for an invalid
operand means the caller-supplied allocator procedure is not invoked in any
mode—not allocation, resize, free, or bulk retirement—before validation
returns. Validator scratch is the only permitted pre-dispatch allocation and
uses its separate allocator with the bounded blocks, exact-size retirement,
and owning failure path above.

Arrays allocate one checked result backing and deep-clone every element in
order. Objects precompute the checked unique member count, allocate one
power-of-two result table, retain left slot order, select the right source
value before cloning a duplicate, and append right-only keys in right slot
order. Keys and all selected values are deep-cloned. This is a shallow merge
only in the jq semantic sense: nested objects are replaced rather than
recursively merged; ownership is still deep and independent. Literal number
identity is copied into a fresh literal payload for null identity and nested
cloning. Direct number+number always dispatches through `number_add` and
therefore returns its inline native result without reimplementing arithmetic.

Nested container cloning is an iterative state machine. Each open Array or
Object construction owns one exact-size, allocator-provenanced linked frame;
frames borrow source and destination payloads reachable from the operation's
source and result roots. A child container root is attached exactly once before
its frame runs. Array initialized counts advance only after child ownership is
attached. Object keys, hashes, buckets, live counts, and next-free counts advance
once before the selected value is attached; completing a child frame resumes
the same parent at its next source slot. No procedure-call depth in addition,
failure unwind, or error destruction scales with `Value` nesting.

Every byte/count/capacity sum is checked before allocation. Exact-length
allocation validation follows the existing scalar, Array, and Object rules.
`Value_Add_Error_Kind` classifies `Invalid_Type_Pair`, `Invalid_Operand`,
`Size_Overflow`, `Out_Of_Memory`, `Allocator_Unsupported`, and
`Cleanup_Failed`; `None` is success. `Value_Add_Error` is opaque and may own a
partial deep result plus an existing `Constructor_Error` for a mismatched raw
allocation. It must be moved with `take_value_add_error` rather than copied.

On a construction failure, completed children and any failed child cleanup
owner are attached to the nearest partial parent before iterative teardown.
This makes one root reach every partial owner even when the inputs alias.
Construction frames are released from their exact remaining linked cursor
before any destination payload they borrow is retired. A failed frame release
keeps that frame, the remaining chain, and the complete partial root owned by
the error for retry; a successful release advances the cursor exactly once.
Cleanup failure takes result precedence: `value_add_error_kind` returns
`Cleanup_Failed`, and `value_add_error_cause` preserves the interrupted
allocation, overflow, or invalid-result classification. An outer unwind may
successfully retry the failed cleanup, in which case the operation still
reports `Cleanup_Failed` but `value_add_error_needs_cleanup` is false. If
cleanup remains incomplete, the error owns the partial root and/or mismatched
allocation. `destroy_value_add_error` retires construction frames first, the
partial Value second, and the raw allocation last; a genuine Free error
preserves the exact cursor, reported cause, and whole error for retry.
`.Mode_Not_Implemented` is successful bulk retirement. Frame allocation maps
exactly to `Out_Of_Memory`, `Allocator_Unsupported`, or a cleanup wrapper for a
nonempty mismatched allocation. Array and Object operation errors likewise
record their interrupted outcome at the source when cleanup wraps it, and the
addition mapper preserves `Out_Of_Memory`, `Allocator_Unsupported`, and
`Size_Overflow` causes. The caller must destroy or transfer every non-success
error before allocator teardown, whether or not it currently reports cleanup
storage.

Scalar payload construction preserves whether its allocator returned
`.Mode_Not_Implemented` in private `Constructor_Error` provenance while its
existing public `Error` kind remains `Out_Of_Memory`. This keeps all direct
constructor consumers and exhaustive public `Error` handling source-compatible
while allowing `value_add` to map String and literal-number construction to
`Allocator_Unsupported`. The provenance survives mismatched-allocation cleanup
ownership and does not alter the size of `Constructor_Error`; it occupies
existing structure padding. Nil success, short success, true
`.Out_Of_Memory`, and checked arithmetic remain classified independently.

Array capacity is an allocation bound, not a minimum representation invariant.
Addition accepts every nonnegative capacity that passes the Array package's
exact extent, initialized/retired ownership, and view bounds. In particular,
the `array_slice` offset-overflow materialization may validly own a nonempty
capacity smaller than `ARRAY_INITIAL_CAPACITY`.

## Alternatives

- Returning a shallow `clone_value` for null identity or container children
  was rejected because independent destruction would still share ownership.
- Building through public append/set mutators was rejected because it adds
  avoidable COW allocations and displaced-owner cleanup boundaries.
- Cloning all left object values before replacing duplicates was rejected
  because it allocates and then fallibly destroys values that are absent from
  the observable merge result.
- Collapsing allocation, invalid operands, type mismatch, and cleanup into one
  boolean was rejected because a future evaluator must map jq type policy
  separately and must never lose retryable cleanup ownership.

## Affected packages and contracts

This delegated decision adds one public Value operation, result enum, opaque
owning error, and Array/Object cleanup-cause accessors under `src/value`.
Array/Object exact-allocation cleanup failures are consistently exposed as
`Cleanup_Failed` with their prior operation outcome available through the new
accessor. It changes no existing signature, package, import edge, package
graph, or root build command. A future evaluator may dispatch its `+` opcode
through this operation, map `Invalid_Type_Pair` to jq's runtime type error, and
propagate or deliberately retire all resource and cleanup failures. It must
keep the explicit allocator and backing state alive until the returned Value
and error are fully retired.

The opaque `Value` payload grows from 40 to 48 bytes to carry the independent
extent, so its one-variant union grows intentionally from 48 to 56 bytes while
remaining alignment 8. `Value_Handle`, a fixed-layout `[6]u64` reserved
for package `value`, is the union variant; the private `value_storage` is
compile-time asserted to match it. The handle retains an exported spelling so
the Odin compiler includes its layout in importing packages, but its declaration
is marked `@(private)`: ordinary external package code cannot name, construct,
type-assert, or assign the six storage words. This gives package `value` and
importing packages one identical 56-byte layout and tag offset without exposing
the storage constructor. The by-value ABI change
also grows `eval`'s private evaluator storage from 248 to 256 bytes because it
owns one `Value`; `Evaluator_Handle` correspondingly becomes `[32]u64` and the
complete `Evaluator` becomes 264 bytes at alignment 8. The external layout test
pins both public layouts and their typed-wrapper guard offsets. Existing
consumers use lifecycle procedures and are rebuilt for these layout changes.

## Validation

Focused tests cover the exact type table, both null sides, mixed rejection,
same-owner arrays and objects, empty containers, nested arrays/objects/strings,
duplicate merge keys, deletion/reinsertion order, right-value replacement,
source/result destruction in both directions, literal/native numeric behavior,
NaNs, infinities, signed zero, direct checked-size helpers, and a malformed
top-level representation matrix with zero allocation in normal and
assertions-disabled modes. Nested malformed String metadata is checked at
shallow and 4,000-level alternating Array/Object depth against mixed and null
partners, with exact zero result-allocator calls and separately measured
scratch allocation/free symmetry. A consistently linked two-slot Object with
independently owned equal-text keys demonstrates length-two, later-value lookup,
and duplicate iteration exposure before preflight rejects it. A legitimate
shared Array payload reached twice below 4,000 alternating Array/Object owners
pins successful completed-node reuse, unchanged COW reference counts, equal
result values, and source-independent result ownership. It and the malformed
4,000-level case run under a 256 KiB process stack; the duplicate-key regression
runs in the same focused command.

Scratch fault injection covers first-allocation `Out_Of_Memory` and
`Mode_Not_Implemented`, short allocation with failed immediate retirement,
later allocation failure with failed block unwind, successful validation with
repeated retirement failure, stable causes, retryable exact-cursor cleanup,
correct free sizes, and zero live blocks. A retired caller-supplied allocator
asserts that malformed input invokes no result-allocator mode at all. A cyclic
graph separately checks termination and no mutation. The construction-frame
matrix covers allocation failure, allocator unsupported, short allocations,
exact-size release, repeated release failure, stable causes, cleanup retry, and
bulk allocators. Separate cleanup-failure injection checks precedence,
source/mapped causes, retryable progress, and no double free. Deterministic
fault injection fails every result allocation boundary and checks zero leaks,
exact frees, unchanged operands, and a healthy retry. The complete Value matrix
runs with threads 1 and 4 in default, debug, speed, assertions-disabled, and
ASan+LSan modes, followed by direct pinned-oracle probes, `make validate`, and
`git diff --check`.

A real 65,537-element Array built through ordinary append operations is sliced
through the 16-bit offset-overflow path to a capacity-one owner; both null
identity directions and Array concatenation prove independent results and
unchanged sources. Scalar allocation probes cover `Mode_Not_Implemented` and
true OOM for string concatenation, both String identity directions, and both
literal-number identity directions, plus short allocation and repeated cleanup
failure/retry with exact frees and inert results.

A separate external package pins the 56-byte/alignment-8 layout and exercises
inert construction, kind inspection, clone, take, addition, error retirement,
and Value destruction. A compile-fail package attempts the reviewed six-word
construction and assignment and must produce the pinned compiler diagnostic
`'Value_Handle' is not exported by 'value'`. The existing evaluator external
layout package continues to pin the resulting 264-byte/alignment-8 Evaluator
layout and full typed-wrapper lifecycle.

Required fresh review lanes are Value ownership/resource safety, jq semantic
parity, and allocation/depth/test-gap falsification.
