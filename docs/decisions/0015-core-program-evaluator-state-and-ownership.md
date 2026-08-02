# 0015: Core Program evaluator state and ownership

- Status: proposed
- Date: 2026-08-02
- Workstream: eval

## Context and evidence

The sealed Program contract now represents Identity, standalone and postfix
Field, Parenthesized, Optional, Fork, and Sequence as an acyclic instruction
graph. The evaluator must preserve jq's generator behavior without native
recursion or a language coroutine.

jq exposes one result per `jq_next`: a top-level return saves a continuation
immediately before returning its owned value, and the next call restores that
continuation (`upstream/jq/src/execute.c:979-999`; accepted evidence
`eval-003`). Exhaustion and a terminal uncaught error remain distinct
(`upstream/jq/src/execute.c:806-819`; accepted evidence `eval-004`). FORK first
saves the current continuation, later enters its alternate branch on ordinary
backtracking, and skips that alternate while an error is being raised
(`upstream/jq/src/execute.c:874-905`; accepted evidence `eval-005`). The CLI
prints every successful result before inspecting a later terminal condition
(`upstream/jq/src/main.c:175-209`; accepted evidence `eval-035`).

String field lookup on an object converts a missing key to null, and indexing
null by a string also returns null (`upstream/jq/src/jv_aux.c:80-87,130-136`).
Other input kinds create the structured “Cannot index KIND with string KEY”
runtime error for short string keys (`upstream/jq/src/jv_aux.c:137-154`). jq
measures the key by its length-delimited byte count but supplies its
NUL-terminated data to `%s`, so an embedded NUL truncates the rendered key
(`upstream/jq/src/jv_aux.c:143-150`;
`upstream/jq/src/jv.c:1293-1297,1446-1449`). Normal INDEX installs that error,
while INDEX_OPT discards it and backtracks empty
(`upstream/jq/src/execute.c:682-709`). General postfix `?` is compiled as a try
whose handler is BACKTRACK (`upstream/jq/src/parser.y:640-642`), and the try
implementation catches errors raised by the protected expression without
catching errors raised by downstream code after an emitted result
(`upstream/jq/src/compile.c:1013-1046`; `upstream/jq/src/execute.c:821-868`).

Executed probes against the repository-built pinned `jq-1.8.1` oracle
confirmed `.`, `.a`, `.a.b`, `(.)`, `.?`, `.a?`, `., .a`, `.|.a`,
`(., .a)|.b`, and `(., .a)?`. In particular, `.a` returned null for `{}` and
null, reported runtime errors for boolean, number, string, and array, `., .a`
on a number emitted that number before the later error, and `(., .a)?`
preserved the number while suppressing only the later runtime error.

An Odin package-layout probe found that the original one-variant public union
used a package-private payload. Both packages reported `Evaluator` as 256 bytes
with alignment 8, while package `eval` reported its payload
`evaluator_storage` as 248 bytes with alignment 8. In an importing package,
`init_evaluator` wrote union metadata at byte offset 256: it changed the `u64`
immediately after an `Evaluator` in a typed wrapper and corrupted allocator
metadata after an exactly sized standalone allocation. The latter evaluated
successfully but its exact free returned `Invalid_Pointer`. Making the union
variant's fixed layout public removed the cross-package disagreement without
changing either reported size.

## Decision

`eval.Evaluator` is an address-stable, exclusive owner containing an explicit
array of resumable frames. Its public representation is a one-variant union
whose variant is the fixed-layout `Evaluator_Handle`, a distinct `[31]u64`.
The 248-byte, alignment-8 handle is reserved for package `eval`, which stores
an identically sized and aligned private `evaluator_storage` in it. Compile-time
assertions pin the handle, storage, and complete 256-byte, alignment-8 union
layout. This retains nil-union construction and existing call sites while
making the payload size, alignment, and tag position identical inside and
outside the package. `init_evaluator` first selects the public handle variant
and then initializes its private storage in place.

`init_evaluator` accepts only an inert Evaluator, a borrowed sealed Active
Program, a live input owner, and an explicit allocator.
It validates the Program and allocates exact initial frame storage before
taking the input. Success transfers the input and leaves the caller's Value
Invalid. Ordinary allocation, size, or validation failure leaves the input
unchanged. If cleanup of a short allocator result itself fails, the Evaluator
retains that allocation as a cleanup-only owner while the input remains with
the caller.

Initialization first re-establishes the canonical complete Program invariants:
Active address-stable lifetime, construction completeness, explicit in-range
root, exact instruction/operand/validation/text slice placement within the
owned allocation, opcode and operand arity/kind/range rules, contiguous text
descriptors, ordered spans, and an acyclic instruction graph. Exact descriptor
checks precede all storage reads. The graph check reuses Program-owned
validation scratch through a non-owning descriptor copy and the canonical
`finalize_program` validator; distinct evaluator initializations serialize
that allocation-free scratch use. Rejection returns `Invalid_Program` before
any evaluator allocation/state publication or input transfer. The caller's
input therefore remains readable, independently owned, and destroyable on
every validation failure.

The Program is borrowed, not copied or reference-counted. Its address and
Active sealed state must remain valid until a terminal step or
`destroy_evaluator` has successfully released all evaluation storage. Every
step validates that lifetime before revalidating a deterministic seal of the
complete execution-relevant logical Program. The seal covers the explicit-root
marker, owned-allocation byte length, instruction and operand collection
lengths, root index, every instruction opcode, operand range and source-span
endpoint, every operand kind and explicit payload field, and every Text
operand's byte length and length-delimited bytes. Program state and owner
address are checked separately as lifetime invariants. Construction
counters and graph-validation records cannot affect an Active Program's
execution or destruction. Stable mixing feeds logical fields and the
destruction-relevant allocation length explicitly; it never reads backing
pointer identity or bytes, struct padding, allocator identity, or
graph-validation scratch. Initialization and each seal walk allocate nothing.
An unsealed Program is rejected at init; a
destroyed/copied Program remains Invalid_Program_Lifetime, while any content
change becomes deterministic Malformed_Program after evaluator cleanup. This
detects API-visible early destruction and mutation, but cannot make a dangling
pointer to already-invalid native storage safe.

Each frame owns one Value representing that activation's logical input.
Children receive `clone_value`; the parent retains its copy while suspended.
Identity and successful Field clone an independently owned result. A root
result transfers through `Step_Result`, and `take_step_output` transfers it to
the caller. The caller must destroy or transfer every yielded Value. Sequence
takes each left output directly into a fresh right activation; therefore no
complete result stream is retained. Fork retains the shared logical input and
evaluates the complete left generator before starting the right generator.
Parenthesized only forwards results. Postfix Field uses a private field-only
activation for each child result, preserving chained generator cardinality.

Optional is an explicit error boundary in the frame-parent chain. A child
runtime error unwinds owned frames through the nearest active Optional and
turns that branch into empty. Values already transferred to callers remain
valid and are not revoked. Optional does not catch errors whose active producer
is downstream of the Optional result. Allocator, short-success cleanup, Value
destruction, arena retirement, and other resource failures are returned as
Resource_Error and leave the exact cleanup state reachable for retry; they are
never converted to empty.

Before publishing a field Runtime_Error, the evaluator copies the complete
length-delimited field key into an independent evaluator-owned allocation.
`Runtime_Error.key` is an immutable borrowed view of that allocation: a step
caller may inspect it but must neither take nor destroy it. It remains valid
through deterministic terminal replay, copied-evaluator rejection, and early
Program destruction, and expires only when `destroy_evaluator` succeeds. This
preserves embedded NUL and lets a future driver reproduce jq's presentation
rule without retaining a Program string. Key allocation or cleanup failure is
a Resource_Error; failed cleanup preserves the exact allocation for retry.
Optional cleanup retires a suppressed key before resuming, while an uncaught
terminal error retains its key until evaluator destruction.

Frames are indexed, never linked by element pointers, so relocation preserves
suspended continuations. The initial arena reserves four frames per Program
instruction. A shared Program DAG can require more simultaneous activations
than any linear instruction bound, so the arena doubles on demand. Growth
allocates and initializes a replacement before raw-transferring frame owners.
If replacement allocation fails, the old arena remains authoritative. If a
short replacement cannot be freed, it is retained as a temporary allocation
with no Values. If freeing the old arena fails after transfer, the replacement
becomes authoritative and the old bytes are retained as a raw non-owning
duplicate for retry. No operation continues until either retained allocation
is retired. `Mode_Not_Implemented` is logical retirement under a bulk
allocator.

Done, Runtime_Error, and Misuse are terminal replay results. Before the first
such result, the evaluator destroys all frame Values and retires all arenas;
cleanup failure returns Resource_Error first, and repeating `step_evaluator`
continues that cleanup before revealing the pending terminal result. A caller
may stop after any output and call `destroy_evaluator`; destruction uses the
same top-down Value cleanup and allocation-retirement order. Genuine Free
failure preserves the owner for deterministic retry. A generated output that
cannot be transferred because live Program mutation invalidates a Sequence or
postfix Field continuation is first transferred to a dedicated pending owner;
terminal cleanup retires that exact owner before reporting Misuse. Terminal
Runtime_Error destruction may still free its retained key and is retryable;
successful destruction is idempotent.

Evaluator assignment is not ownership transfer. The owner stores its address;
step and destroy reject an accidental shallow copy before consulting Program,
frame, Value, or allocator state. The API is deliberately exclusive and not
thread-safe: callers must not step or destroy the same owner concurrently.
Odin cannot prevent overwriting an owner or restoring a stale byte-for-byte
copy at the original address; doing either is outside the public contract.

`Step_Result` owns a Value only for Output and must not itself be shallow
copied. Runtime errors contain a kind, input Value kind, Program source span,
and the borrowed evaluator-owned key view described above. Copying a
Runtime_Error copies only that view and does not extend its lifetime. Resource
results contain the exact `runtime.Allocator_Error`. Misuse is separate from jq
runtime errors so invalid lifecycle operations cannot be suppressed by
Optional.

## Alternatives

Native recursion was rejected because supported Program depth is
allocator-bounded rather than process-stack-bounded. Coroutines, OS threads,
capturing closures, and eager output arrays were rejected because they either
do not exist in the pinned Odin toolchain or violate pull-based generator and
early-cancellation semantics.

A fixed frame count derived only from Program instruction count was rejected
because shared DAG children can be activated repeatedly while Sequence keeps
earlier producers suspended. Element pointers were rejected because growth
would invalidate them. In-place allocator Resize was rejected because a short
or relocated result complicates preservation of the old owner; explicit
replacement makes every ownership transition visible.

The copyable registry capability used by the bounded prototype was not adopted
for this first Program evaluator. It globally serializes machines and adds a
heap control block independent of the caller allocator. The production slice
instead rejects ordinary accidental copies and documents the remaining Odin
byte-copy limitation.

Increasing the caller's allocation or adding padding after `Evaluator` was
rejected because it would hide an incorrect public type layout and leave typed
wrappers unsafe. Replacing `Evaluator` with a plain struct was unnecessary and
would have removed the nil-union lifecycle used by existing callers. Exposing
the semantic fields of `evaluator_storage` was rejected because callers need
the representation's layout, not access to the ownership state machine.

## Consequences

The new public contract affects `eval` and future driver consumers. `program`
and `value` are direct unchanged dependencies; `compiler`, the package graph,
root build files, and CLI remain unchanged. The evaluator supports only the
currently sealed core Program opcodes. It does not format user-facing jq error
text, provide a candidate executable, implement unsupported builtins/grammar,
or make owner operations concurrent.

Complete seal verification is linear in Program size on every nonterminal
step. Independent review measured approximately 14.4 ms for 500 outputs,
57.3 ms for 1,000, 227.7 ms for 2,000, and 918.2 ms for 4,000. This quadratic
total cost for long output streams is an accepted known limitation of the
mutation-detection contract in this slice; changing the ownership or mutation
contract, adding write mediation, or redesigning verification is deferred.

## Validation

- Test each supported core form and jq order/cardinality, including missing
  fields, output-before-error, Optional output-before-suppressed-error, and
  Sequence over multiple left outputs.
- Pull exactly one output per call; stop after the first of many Fork outputs
  and destroy every suspended owner.
- Evaluate 10,000-deep Parenthesized, Optional, Sequence, and Fork Programs on
  the normal 8 MiB stack, plus a shared-DAG shape that forces arena growth.
- Reject unsealed, destroyed-too-early, malformed, copied-Program, and copied-
  Evaluator misuse wherever the public contracts permit detection.
- Before initialization allocation or input transfer, reject missing/out-of-
  range roots, incomplete counters, malformed opcode/span/operand/text/graph
  structure, and safely constructible owned-slice descriptor corruption;
  prove a nested heap input remains readable and independently destroyable.
- Inject initial and growth allocation failure, short allocation success,
  Value Free failure, old-arena Free failure, final arena Free failure, and
  cleanup retry. Require zero leaks and bad frees under Odin tracking and ASan.
- Mutate live Sequence and postfix Field operands after initialization, require
  Resource-before-Misuse cleanup retry for heap-backed pending outputs, and
  preserve distinct and embedded-NUL field keys through terminal replay,
  Program destruction, and evaluator-key cleanup retry.
- Mutate dormant descendants, source spans, collection lengths, and Field text
  bytes and lengths while output, runtime-error work, and terminal-cleanup retry
  states are pending; require cleanup-before-Misuse and exact terminal replay.
- Run evaluator tests with one and four test threads in default, debug, speed,
  assertions-disabled, and debug+ASan configurations; then run `make validate`.
- From a separate Odin package, pin the 256-byte/alignment-8 public layout and
  typed-wrapper offsets; preserve distinct adjacent guards through init,
  output, Done, runtime-error replay, Program-lifetime Misuse replay, cleanup
  failure/retry, and destroy; allocate exactly 256 aligned bytes and require
  its exact free to succeed after evaluation and destruction.
- Required independent review lanes: source-aware semantic parity, Odin
  ownership/resource safety, and generator/failure-path test-gap review.
