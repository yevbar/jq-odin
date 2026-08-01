# 0010: Object Value ownership, order, and copy-on-write mutation

- Status: proposed
- Date: 2026-08-01
- Workstream: value

## Context and evidence

jq objects are refcounted tables whose slots store collision linkage, a hash,
an owned string key, and an owned value. A fresh object has eight slots and
twice as many hash buckets (`upstream/jq/src/jv.c:1563-1603,1825-1828`). New
keys take successive `next_free` slots; replacement retains the existing slot
and releases the incoming duplicate key
(`upstream/jq/src/jv.c:1650-1660,1734-1746`). Iteration scans increasing slot
indices and skips deleted slots (`upstream/jq/src/jv.c:1924-1952`). Therefore
bucket or Odin map iteration cannot define jq-compatible `keys_unsorted` order.
jq documents that order as roughly insertion order
(`upstream/jq/docs/content/manual/v1.8/manual.yml:935-952`).

Mutation reuses an unshared object. A shared object is copied at the same table
size, preserving slot indices and buckets while retaining every occupied key
and value (`upstream/jq/src/jv.c:1708-1731`). A full unique table doubles and
rehashes by transferring occupied key/value references in old slot order,
skipping deletions (`upstream/jq/src/jv.c:1685-1705`). Deletion unshares first,
unlinks the bucket chain, releases the stored key/value, and leaves a hole
rather than reusing the slot (`upstream/jq/src/jv.c:1762-1780`).

Lookup returns a retained value or invalid on a miss
(`upstream/jq/src/jv.c:1830-1842`). Equality is independent of table size and
insertion order: it looks up every occupied left key in the right object,
recursively compares values, and requires equal member counts
(`upstream/jq/src/jv.c:1783-1805,1996-2027`). Final release walks every occupied
slot, releases its key and value, then frees the table
(`upstream/jq/src/jv.c:1671-1683`).

Bounded probes used the official jq 1.8.1 Linux AMD64 binary, reporting
`jq-1.8.1` with SHA-256
`020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d`.
They establish duplicate-key replacement, replacement without reordering,
delete/reinsert order, growth order through forty keys, order-independent
recursive equality, and duplicate JSON-key behavior:

```sh
/tmp/jq-object-oracle-1.8.1 -cn '{a:1,b:2,a:3} | [., keys_unsorted]'
/tmp/jq-object-oracle-1.8.1 -cn '{a:1,b:2,c:3} | .b=20 | [., keys_unsorted]'
/tmp/jq-object-oracle-1.8.1 -cn \
  '{a:1,b:2,c:3} | del(.b) | .d=4 | .b=5 | [., keys_unsorted]'
/tmp/jq-object-oracle-1.8.1 -cn \
  'reduce range(0;40) as $i ({}; .["k\($i)"]=$i) | keys_unsorted'
/tmp/jq-object-oracle-1.8.1 -cn \
  '[({a:[1,{x:2}],b:3} == {b:3,a:[1,{x:2}]}), ({a:1} == {a:1,b:null})]'
printf '%s\n' '{"z":0,"a":1,"z":2,"m":3}' | \
  /tmp/jq-object-oracle-1.8.1 -c '[., keys_unsorted]'
```

The results respectively preserve `a,b`; preserve `a,b,c`; produce
`a,c,d,b`; produce `k0` through `k39`; report `true,false`; and preserve
`z,a,m` while giving `z` its final value.

Odin allocator frees can fail, while jq's allocator aborts or nonlocally exits
on allocation failure (`upstream/jq/src/jv_alloc.c:12-43,108-147`). An Odin
mutator therefore cannot internally release an overwritten or deleted owner
and still promise transactional failure. The established Array contract solves
the same mismatch by returning displaced owners.

## Decision

`Kind.Object` uses the existing opaque owning `Value` handle and the existing
package-private refcounted payload. The payload owns a single allocation
containing an object header, power-of-two slot array, and twice as many bucket
heads. Initial capacity is eight. Hash buckets provide lookup only; observable
traversal always scans slots in increasing index order.

The public API is deliberately small:

- `object_value(allocator)` creates an empty owning Object identity.
- `object_length` borrows a live Object.
- `object_get_copy` borrows the Object and string bytes and returns an
  independently owned value handle on a hit.
- `object_set_take` takes owned string-key and value handles on success. For a
  replacement it returns the unused incoming duplicate key and prior value as
  owners. On failure both inputs remain owned and logically unchanged.
- `object_delete_take` borrows string bytes and, on a hit, returns the stored
  key and value as owners. A miss changes nothing.
- `Object_Iterator` contains only a slot position. `object_iter_next_copy`
  borrows the same live, unmutated Object and returns independently owned key
  and value handles. The iterator retains no pointer or view; mutation, take,
  or destruction invalidates its traversal contract.
- `clone_value`, `take_value`, `destroy_value`, and `values_equal` extend to
  Object without changing signatures.

Every returned owner must be transferred or destroyed exactly once. Ordinary
assignment remains forbidden as an ownership operation. String views obtained
from returned key copies follow the existing borrowed-string lifetime and do
not survive destruction or mutation of that owning key handle. No raw slot,
bucket, slice, map element, or mutable pointer crosses the package boundary.

Cloning shares the table. Shared mutation allocates an equal-capacity table
with the original allocator, validates exact allocation length, retains every
occupied key/value, copies holes and bucket linkage, and only then decrements
the old reference and installs the copy. Unique insertion uses successive free
slots. A full unique table allocates double capacity, transfers occupied owners
in increasing old-slot order, retires the old allocation, and installs the
replacement. It never uses allocator Resize. Deleted holes are skipped during
growth and are not reused before growth, matching jq order.

Construction, COW, and growth accept only exact-length allocations. Nil,
short, explicit allocation errors, and unsupported allocators leave logical
operands unchanged. Any nonempty mismatched temporary or replacement whose
Free genuinely fails is retained in the opaque owning Object operation error
for retry; `.Mode_Not_Implemented` is successful bulk retirement. If retiring
the old unique table fails during growth, the original remains authoritative
and unchanged; the raw-transfer replacement is retired without recursively
releasing its duplicate bits.

Final Object release walks occupied slots in order. A nested key/value release
failure moves the payload into a private cleanup-only state and records the
exact key/value phase and next slot. The owning handle remains transferable
and retryable through `take_value`/`destroy_value`, but lookup, length,
iteration, clone, equality, and mutation reject it. Retry resumes without
double release. A later backing-allocation Free failure likewise leaves the
deterministic cleanup-only owner for retry. `.Mode_Not_Implemented` retires
the handle under the allocator's bulk lifetime.

Recursive equality uses key lookup and member count, so insertion order,
capacity, deletion holes, sharing, and rehash history are irrelevant. Same
payload identity is a fast path only for live, non-retiring objects.

## Alternatives

- Odin `map[string]Value` was rejected because map iteration cannot implement
  jq slot order and map mutation would expose pointer-lifetime hazards.
- A sorted structure was rejected because `keys_unsorted`, printing without
  sorted mode, replacement, and delete/reinsert expose insertion history.
- Deep-copying clone was rejected because jq deliberately shares and detaches.
- Destroying duplicate/displaced/deleted owners inside mutation was rejected
  because allocator Free failure would make rollback impossible.
- Reusing deletion holes was rejected because jq leaves them empty until a
  later rehash and iteration observes subsequent inserts after older slots.

## Affected packages and contracts

This extends the shared `Value` API under the coordinator's explicit Object
delegation. It adds no package or import edge and changes no existing scalar or
Array signature. Future `json` constructs duplicate keys by handling the two
returned replacement owners; `eval` handles mutation/deletion owners; and
`program` retains Object constants only with `clone_value`. Those consumers
must keep captured allocator state alive until final retirement and must
propagate or deliberately handle Object operation errors.

## Validation

Focused allocation-tracked tests cover empty, replacement, duplicate keys,
lookup, small/large growth, ordered iteration, deletion/reinsert, COW aliases,
recursive equality, nested arrays/objects/strings/literal numbers, allocator
provenance, exact-length mismatch cleanup, allocation failure, old-table Free
failure, nested and backing Free retry, arena retirement, invalid/retiring
handles, and aliased/wrong operands. Strict optimized, debug, debug with
ASan/LSan, assertions-disabled, `make validate`, and the bounded jq probes are
required before handoff. Fresh semantic-parity, Odin ownership/safety, and
allocation/failure-injection test-gap review lanes are required.
