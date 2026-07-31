# 0005: Fallible final Value destruction

- Status: proposed
- Date: 2026-07-31
- Workstream: value

## Context

Decision 0003 made `destroy_value` the retirement point for an owning `Value`
handle and allowed `.Mode_Not_Implemented` as successful retirement for
bulk-lifetime allocators. The first implementation invalidated the handle and
decremented its final reference before calling the captured allocator. It used
an `assert` to reject every other free error.

Assertions are elidable in supported Odin builds. A genuine allocator error
could therefore return normally after the only owner was invalidated, losing
the allocation and any deterministic way to report or retry the failure.
This is an Odin ownership defect; it does not change jq scalar semantics or
the source evidence recorded by decision 0003.

## Decision

`destroy_value(value: ^Value)` returns `runtime.Allocator_Error`.

- Destroying nil, an invalid handle, an inline value, or a non-final payload
  handle succeeds and leaves the supplied handle invalid.
- A successful ordinary final free invalidates the supplied handle.
- `.Mode_Not_Implemented` remains successful final-handle retirement. The
  payload reference count becomes zero and its storage remains owned by the
  allocator's documented bulk lifetime.
- Any other final-free error is returned in every build mode. The supplied
  handle and its final reference remain unchanged, so the caller retains
  ownership and may inspect, transfer, clone, or retry destruction while the
  captured allocator and its backing state remain valid.

Allocator callbacks must follow Odin's allocator error contract: returning an
error from `.Free` means the allocation was not freed.

## Alternatives

- A non-elidable panic would make the failure visible but would prevent
  deterministic recovery and retry.
- Invalidating before free and returning the error would still lose the last
  owner.
- Treating every free error as bulk retirement would hide allocator defects
  and conflate them with the explicit `.Mode_Not_Implemented` contract.

## Affected packages and contracts

The public ownership contract in decision 0003 is refined by the fallible
return. The only current direct consumers are the tests in `src/value`.
Future `json`, `program`, and `eval` consumers must handle or deliberately
propagate destruction errors when they own values. No package edge changes.

## Validation

- An allocator returns `.Invalid_Pointer` on its first `.Free`; destruction
  returns that error with assertions disabled, preserves the owner, and a
  later retry frees exactly once.
- Ordinary final free, `.Mode_Not_Implemented` bulk retirement, clone/non-final
  destruction, and repeated destruction remain covered.
- Run focused and full value tests with allocation tracking,
  fail-on-bad-memory, and AddressSanitizer, followed by `make validate`.
- Request fresh exact-head ownership/safety and semantic-parity reviews.
