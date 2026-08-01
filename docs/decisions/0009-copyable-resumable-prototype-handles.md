# 0009: Copyable handles for the resumable evaluator prototype

- Status: proposed
- Date: 2026-07-31
- Workstream: eval

## Context and evidence

The prototype must expose zero-to-many results through explicit resumable
state. jq restores a saved continuation on each `jq_next`, returns values one
at a time, and distinguishes exhaustion from a terminal error
(`upstream/jq/src/execute.c:343-353,806-819,979-1000`; accepted evidence
`eval-003` and `eval-004`). The range fixture fixes left-major Cartesian order
(`upstream/jq/tests/jq.test:307-309`; accepted evidence `eval-006`). The limit
and first fixtures prove that early cancellation must not evaluate a later
error (`upstream/jq/tests/jq.test:361-375,409-412`; accepted evidence
`eval-036` and `eval-037`). The CLI emits each valid result before reporting a
later error (`upstream/jq/src/main.c:175-209`; accepted evidence `eval-035`).

jq teardown first nulls the caller's state pointer, then resets and frees the
state (`upstream/jq/src/execute.c:1124-1135`; accepted ownership evidence
`eval-own-018`). Its reset unwinds saved forkpoints and releases retained
values before freeing stack storage (`upstream/jq/src/execute.c:273-327`;
accepted evidence `eval-008` and accepted ownership evidence `eval-own-003`,
`eval-own-008`, and `eval-own-030`).

Odin dev-2026-05 permits shallow struct assignment and does not support
`#no_copy`. The prior prototype stored dynamic-array descriptors directly in
the caller-held machine and tried to reject copies with a self-pointer and a
lifetime token. A caller could copy the machine, destroy the original, and
assign the stale copy back at the original address. That restored both the
self-pointer check and freed descriptors, permitting use-after-free and
double-free.

## Decision

For this bounded prototype, `prototype_machine` is a copyable non-owning
capability containing only a process-unique integer identifier plus terminal
replay data. All live mutable state, allocator-bearing dynamic arrays, and
cursor/frame state live in a package-allocated `prototype_machine_state`.

Live states form an intrusive package registry:

- the state allocation itself is the registry entry, so the registry has no
  separate allocation or fallible growth;
- one package mutex covers registry lookup, claim, unlink, and control-block
  retirement; a claimed state remains linked but rejects concurrent copied
  handles, and caller allocator callbacks run only while that mutex is
  unlocked;
- claim classifies the identifier as claimed, busy/in-flight, or absent/stale
  atomically while holding that mutex; callers consume that captured
  classification without a second lookup, so an observed busy state cannot be
  reclassified as absent after concurrent retirement;
- identifiers increase monotonically and are never reused; exhaustion makes
  future initialization fail, preventing ABA;
- the control block uses `runtime.heap_allocator`, while nodes, offsets, and
  frames use the explicit caller allocator recorded in the state;
- every terminal step, whole-machine stop, or destroy transactionally releases
  caller-allocator storage, then unlinks and frees the control block exactly
  once with `runtime.heap_allocator`;
- initialization assigns an identifier and links a busy control block before
  invoking the caller allocator, so a reentrant callback can observe only
  `operation_in_progress`; caller-allocator setup failure unlinks and frees
  that control block before returning an inert handle (or preserves the linked
  cleanup owner if the fixed heap allocator rejects that free);
- after the final live state is retired, the registry head is nil and owns no
  allocation.

Every dynamic-array `Free` is error-bearing. A nil result retires the
descriptor normally; `Mode_Not_Implemented` also retires it logically because
the allocator owns a bulk lifetime. Any other allocator error preserves the
descriptor, allocator, control block, registry link, and sole reachable owner.
Cleanup progresses in deterministic order: rollback offsets, rollback frames,
active frames, node-owned offsets in slot order, and the node array. Descriptors
whose frees succeeded are cleared, while the first rejected descriptor remains
unchanged for retry. The caller allocator is cleared only after all of its
descriptors retire. Registry unlink occurs only after that point. A genuine
control-block `Free` failure relinks the unchanged control block before the
registry mutex is released.

The private `prototype_state.cleanup_failed` state records the exact cleanup
operation (`add_rollback`, `start_rollback`, `terminal_step`, `stop`, or
`destroy`), the intended terminal state, and the allocator error. Terminal
stepping returns `prototype_step_kind.cleanup_error` plus that allocator error;
it does not report exhaustion or the pending jq runtime error until a repeated
step completes cleanup. `prototype_stop` and `prototype_destroy` return the
allocator error and leave the handle live; repeating the same operation retries
the preserved descriptor. Add and start rollback retain their unpublished
dynamic arrays in the control block; repeating the same add or start first
retries rollback, then repeats construction. Other build/start mutations are
rejected while cleanup is pending; destroy may instead retire the complete
pending owner transactionally. `operation_in_progress` is the deterministic step
result for a copied handle that encounters an in-flight claimed operation;
stop/destroy report `Invalid_Argument` and never clear that handle.

Ordinary assignment copies a non-owning capability and is supported. Copies
share the same live machine and may advance, stop, or destroy it. The first
terminal step, stop, or destroy retires the shared live state. The particular
handle used for a terminal step retains only exhaustion or error replay data;
other copies retain a stale identifier, fail every mutation and node-handle
check, step as exhausted, and can be destroyed without allocation access.
There is no clone operation and no copied handle owns a reference count or a
separate allocation.

Destroy zeros the supplied handle. Restoring a stale ordinary copy afterward
restores only an integer that is absent from the registry, never an address or
dynamic-array descriptor. Reinitialization requires an inert zero handle and
gets a new identifier. Node handles contain that identifier and a stable slot,
so old and cross-machine node handles fail.

The allocator and everything reachable through `allocator.data` must remain
valid until terminal stepping, stop, or destroy has returned success. A genuine
cleanup error extends that borrow through all retries. Once cleanup succeeds,
replay and stale-handle operations never consult the retired allocator. The
package heap allocator is independent and must remain available until the
operation itself returns.

## Alternatives

- Another self-pointer, generation token, or Mutex-based no-copy convention
  was rejected because shallow assignment can restore all of those fields and
  the pinned compiler does not enforce no-copy behavior.
- A caller-visible pointer to an allocated control block was rejected because
  an uncounted shallow pointer copy becomes a dangling pointer when another
  copy destroys the block.
- Reference counting was rejected because ordinary Odin assignment cannot
  increment a count.
- Permanent tombstone allocations were rejected because copied handles have
  unbounded lifetimes and the tombstones would leak.
- A separately allocated map or growable registry was rejected because it
  adds allocator provenance, failure, cleanup, and ABA complexity without
  improving this prototype. The intrusive list is intentionally bounded in
  scope and may be replaced before a production evaluator API is accepted.

## Consequences

Only the eval prototype and its focused tests consume this contract. No import
edge or cross-package public type changes. The registry serializes prototype
machines, which is acceptable for a semantic prototype but is a known
scalability limitation. A production evaluator should revisit handle lookup
and concurrency after its program/value contracts exist.

## Validation

- Restore an ordinary stale machine copy after destroy and exercise add,
  start, step, stop, repeated destroy, and reinitialize under allocation
  tracking and ASan.
- Prove copied handles share live advancement and become harmless stale
  capabilities after retirement.
- Reject old node handles after destroy/reinitialize and handles from another
  machine.
- Inject every caller-allocator allocation/resize failure and prove atomic
  cleanup, recorded-allocator release, and no post-retirement allocator call.
- Reject every observed `Free` once (and the same `Free` repeatedly), prove the
  descriptor and registry owner remain reachable, retry the same logical
  operation, and finish with zero leaks or bad frees. Cover partial-add
  rollback, terminal exhaustion/error, building/active stop, destroy, stale
  copies, and `Mode_Not_Implemented`. Frame append rollback is unreachable in
  this acyclic prototype because start reserves `len(nodes) >= 1` frames before
  its single append; its rollback descriptor nevertheless follows the same
  transactional contract.
- Reenter the evaluator from caller allocator allocation and free callbacks to
  prove the global registry mutex is not held and the in-flight state cannot be
  retired or revived through a stale/ABA alias.
- Preserve zero/one/many, Cartesian order, empty, early cancellation,
  output-then-error, terminal replay, and scoped-stop tests.
- Run debug and debug+ASan eval tests, then `make validate`.
- Required review lanes: source-aware semantic parity, Odin ownership/safety,
  and allocation-failure/test-gap review.
