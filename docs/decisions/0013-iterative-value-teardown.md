# 0013: Iterative Value container teardown

- Status: proposed
- Date: 2026-08-01
- Workstream: value

## Context and evidence

Final jq Array release visits every owned element with `jv_free` before it
frees the backing allocation (`upstream/jq/src/jv.c:846-854`). Final Object
release similarly visits occupied slots, releases each key and recursively
dispatches each value through `jv_free`, then frees the table
(`upstream/jq/src/jv.c:1671-1682`). Generic `jv_free` dispatches nested arrays
and objects back to their kind-specific final-release procedures
(`upstream/jq/src/jv.c:1964-1981`). These source facts define ownership and
release order, but jq's recursive C call structure is not an observable value
semantic that the Odin implementation must retain.

The existing Odin `destroy_value` mirrored that recursion. A chain of 10,000
owned arrays exhausted the normal 8 MiB process stack in a debug AddressSanitizer
build, although raising the stack limit masked the problem. Destruction must
also retain the established Odin refinement that allocator `Free` may fail:
all progress before the failure remains committed, while the root owner and
remaining work stay reachable for retry.

## Decision

Final Array and Object destruction is an iterative depth-first traversal. Each
private container payload carries one intrusive parent-continuation pointer.
The existing Array cleanup index and Object slot/key-phase cursor identify the
next owned child. Descending into a final nested container links that child to
its parent; completing it returns through the link and advances the parent
cursor. Consequently teardown uses bounded procedure call depth for arbitrary
array/object mixtures.

The traversal allocates no separate worklist and never calls an allocator to
grow teardown state. It therefore has no new arithmetic or allocation-failure
boundary: explicit state is bounded to one pointer already inside each
allocated container payload. Existing checked allocation-size calculations
now include that private header field automatically. Tests make all further
allocations fail once teardown begins and verify that destruction and retry
perform no allocation attempt.

Reference counting is unchanged. A non-final child reference is decremented
and its owning slot invalidated without traversing the shared payload. A final
container becomes cleanup-only before its first child is released, so clone,
inspection, equality, and mutation continue to reject partial retirement.
Array initialized and private-retirement-tail owners retain their established
order; Object keys and values retain slot order and key-before-value phases.

Successful child releases advance the owning container cursor exactly once.
If any scalar, nested-container, or container-backing `Free` returns a genuine
error, the cursor remains at the failing owner. Every ancestor still owns the
unchanged child slot, and intrusive parent links plus cleanup cursors preserve
the complete continuation. A retry from the original root descends to that
owner without repeating completed releases. `.Mode_Not_Implemented` continues
to mean successful retirement under the originating allocator's bulk
lifetime. Allocator provenance remains attached to every payload and every
backing allocation is freed only through its captured allocator.

## Alternatives

- A recursive helper was rejected because it preserves the stack-overflow
  failure at jq-supported nesting depths.
- A dynamically growing external worklist was rejected because it introduces
  teardown-time allocation, checked-growth, and recoverable partial-worklist
  ownership states that are unnecessary when final containers already own
  stable continuation storage.
- A fixed-size local stack was rejected because it would impose a new nesting
  limit or require a recursive/allocating overflow path.
- Advancing a parent before releasing its child was rejected because a failed
  child `Free` would make the still-owned child unreachable on retry.

## Affected packages and contracts

The public `Value`, `destroy_value`, error, reference-counting, COW, allocator,
and retiring-handle contracts and signatures do not change. The private
payload layout gains one continuation pointer, so allocation sizes change only
inside `src/value`. No package or import edge changes.

`json`, `program`, `compiler`, and `eval` require no source change. They retain
their existing obligation to handle fallible destruction and keep captured
allocator state alive until retirement succeeds. This decision refines the
implementation of decisions 0005, 0007, and 0010 without changing their public
ownership requirements.

## Validation

Checked-in tests destroy 10,000 nested arrays and a 10,000-level mixed
array/object chain with the normal process stack. Further tests cover nested
sharing/COW, allocation rejection during teardown, a genuine `Free` failure
after partial mixed-container progress, allocation-free retry, no leak or
double free, and preserved cleanup-only state. Existing Value tests continue
to cover Array/Object backing failures, nested leaf failures,
`Cleanup_Failed`, retiring owners, and bulk allocators.

Run the Value suite with strict memory tracking in default, debug, optimized,
assertions-disabled, and debug AddressSanitizer modes without changing the
process stack, followed by `make validate`. Fresh semantic-parity, Odin
ownership/resource-safety, and allocation/failure/depth test-gap review lanes
are required.
