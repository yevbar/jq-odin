# 0014: Neutral core-filter Program IR

- Status: proposed
- Date: 2026-08-02
- Workstream: program

## Context and evidence

jq gives pipe right associativity, comma left associativity, and postfix forms a
tighter precedence (`upstream/jq/src/parser.y:100-113`). The parser lowers pipe
by ordered block joining but lowers comma through `gen_both`
(`upstream/jq/src/parser.y:324-345`). Ordered block joining splices the second
block after the first (`upstream/jq/src/compile.c:259-262`), while `gen_both`
emits explicit `FORK` and `JUMP` control around its two branches
(`upstream/jq/src/compile.c:601-606`). The opcode set separately names `INDEX`,
`INDEX_OPT`, `FORK`, `JUMP`, and `BACKTRACK`
(`upstream/jq/src/opcode_list.h:11-20`), and index construction selects normal
or optional indexing explicitly (`upstream/jq/src/parser.y:175-181`).

Upstream attaches source locations to emitted instructions that do not already
have one and creates simple one-op instructions
(`upstream/jq/src/compile.c:120-143`). Its flattened bytecode measures base
forms in 16-bit units and derives variable operation lengths from those forms
(`upstream/jq/src/bytecode.c:8-20,40-45`). This IR need not reproduce that
encoding, but leaving host-sized indices and implicit control would make later
overflow and generator behavior accidental.

The merged syntax contract provides a flat, parser-owned arena for exactly
identity, standalone/postfix field access, retained parentheses, comma, pipe,
and postfix optional. Its nodes and source spans are borrowed and become
invalid when parser destruction begins. A compiled program therefore cannot
retain AST slices or field-name slices.

## Decision

`program.Program` is a neutral flat instruction graph. It imports neither
`syntax` nor `eval`. `compiler.lower_filter` is the only AST-to-IR boundary in
this slice and imports both `syntax` and `program`. No evaluator or runtime
frame is part of the contract.

There is one instruction per syntax-arena node, retained in deterministic arena
order, plus a fixed-width root instruction index. Instructions explicitly name
`Identity`, `Field`, `Parenthesized`, `Sequence`, `Fork`, and `Optional`.
`Sequence` has ordered left and right instruction operands and represents pipe's
sequential generator composition. `Fork` has ordered left and right instruction
operands and requires independent resumable branch/cardinality behavior. It is
the graph-level equivalent of jq's fork/jump region: explicit child edges bound
both branches, so a separate linear jump operand is unnecessary. `Optional`
wraps one child instruction and records suppression intent without executing or
rewriting that child. `Parenthesized` remains explicit for exact source spans.

Instruction indices, operand indices, text offsets, source offsets, counts, and
the total storage byte count are distinct `u32`-backed types. Opcodes and
operand tags use `u8`. Every instruction carries a half-open `Source_Span` with
`u32` start/end offsets. Compiler validation rejects invalid source spans,
invalid child indices, transient/inconsistent AST flags, any individual count
above `u32`, source offsets above `u32`, and cumulative layout above `u32`.
Arithmetic is checked in `u64` before narrowing. Overflow is reported as
`Size_Overflow` before allocation, leaving no partial owner.

Instruction references are not constrained to child-before-parent arena order.
The iterative syntax parser appends a Pipe placeholder before parsing its
right-hand term and later installs that term as the right child
(`src/syntax/parser.odin:301-327`), so valid Programs can contain forward edges.
Shared children and unreachable arena nodes are also valid. Consequently,
finalization validates the complete allocated graph, rather than only the
selected root, and rejects self-cycles and longer cycles before sealing.

Fields store their name in program-owned, length-delimited text storage. A
standalone field has one Text operand and applies to implicit input; a postfix
field has its child Instruction operand first and Text operand second. Programs
store byte offsets only, not `diagnostic.Source` identities or string views, so
their lifetime is independent of the parser and source backing storage.

One caller-selected allocator supplies one exact contiguous allocation holding
instructions, operands, private graph-traversal records, and text. There is one
zero-initialized traversal record per instruction. Finalization reinitializes
and uses those records for an iterative depth-first color traversal, so graph
validation allocates nothing, does not recurse on the native stack, admits
forward edges and shared DAG children, and remains safe for deeply nested valid
forms. The private records are never exposed and remain harmlessly Program-owned
until the one allocation is destroyed. This eliminates growth, clone boundaries,
element-pointer invalidation, and rollback between multiple successful
allocations. Exact allocation begins an explicit `Building` state. Construction
setters fill instruction and operand slots and text ranges exactly once in
order, and reject every call outside `Building`. The builder records one
explicit fixed-width root, and finalization proceeds only after it is present,
all exact storage is filled, and the finite acyclic instruction graph, operand
ranges, text ranges, spans, and references validate. It then seals the
address-stable owner by transitioning exactly once to `Active`. Missing or out-of-range roots,
incomplete storage, structural errors, and repeated finalization are rejected
without making the Program readable. A
zero-count allocation is valid Building storage but cannot be finalized because
it has no owned entry instruction.

Runtime access is unavailable in `Building`. Active instruction and operand
counts are returned as fixed-width `Count` values, and indexed access returns
`Instruction` and `Operand` structs by value rather than mutable slices. The
only borrowed runtime view is the immutable `string` returned for a valid Text
operand. Its backing remains owned by the live Program and the view expires
when Program destruction begins. A live Program must not be copied. This slice
defines no clone or ownership transfer operation. Odin does not provide field
privacy for public structs, so direct field rewriting is outside the valid API;
the supported builder and runtime APIs enforce sealing without a second
allocation.

Allocation errors preserve the exact `runtime.Allocator_Error`. A nil or
short successful allocator result is rejected. If malformed returned storage
cannot be retired because Free fails, Program records `Cleanup_Failed`, retains
the allocator and exact slice, and requires `destroy_program` retry. Ordinary
allocation and overflow failures leave the output inert. `Mode_Not_Implemented`
retires storage under the allocator's bulk lifetime. Before destruction of any
`Building`, `Active`, or `Cleanup_Failed` value, `destroy_program` explicitly
checks the address-stable owner identity. A shallow copy is rejected with
`runtime.Allocator_Error.Invalid_Pointer` before backing or allocator access and
without changing the copy, original, or retry state. Successful destruction is
idempotent for genuine owners and inert `Uninitialized`/`Destroyed` values; a
genuine Free error preserves the sole owner for retry. No storage uses or
escapes `context.temp_allocator`.

## Alternatives

Copying jq's intrusive compiler blocks and 16-bit bytecode was rejected because
this slice has no bindings, constants, or evaluator and should not inherit
pointer ownership or an encoding cap accidentally.

Flattening pipe and comma into the same instruction sequence was rejected
because comma requires independently resumable generator branches while pipe
feeds each left result sequentially to the right.

Erasing parentheses or optional was rejected because the former loses exact
source-form spans and the latter would execute or prematurely encode error
suppression policy.

Retaining `diagnostic.Span` and borrowed field slices was rejected because it
would extend the parser/source lifetime into compiled-program ownership.

Separate dynamic arrays were rejected because each growth/allocation creates
additional rollback states and risks stale slice or element pointers. Recursive
AST lowering was rejected because supported nesting is allocator-bounded rather
than call-stack-bounded.

Requiring every child instruction index to precede its parent was rejected
because supported Pipe arenas contain a forward right-child edge. Allocating a
second temporary traversal table was rejected because it would add allocator
failure and cleanup ownership to finalization; reserving private records in the
already checked exact Program layout preserves the single-owner contract.

## Consequences

Affected packages and owners are `program` (new public IR, ownership, and
cleanup contract), `compiler` (new lowering API), `syntax` (direct borrowed
input consumer, unchanged), and future `eval` (direct Program consumer,
unchanged and not yet wired). The program and compiler workstream owns the
implementation; language and eval owners must review the public sequencing,
fork, optional, span, and lifetime contract before depending on it.

There is no new package or import edge. `program` imports no project package;
`compiler` uses graph-permitted `syntax`, `program`, and `diagnostic` imports.
No existing direct consumer required migration. Future evaluator work must
interpret `Sequence` and `Fork` with jq generator semantics, use only the sealed
count/index/text accessors, and must not import `compiler`.

This slice intentionally does not execute programs, lower unsupported syntax,
add grammar, constants, a driver, or the rest of jq.

## Validation

Focused tests inspect every supported form, precedence and association,
deterministic instruction/operand order, explicit root selection with
unreachable arena nodes, complete-graph self/multi-node cycle rejection,
forward edges and shared DAG children, every instruction span, owned field text
after parser/source destruction, fork versus sequence, deep non-recursive
lowering/destruction, Building access rejection, incomplete/invalid/out-of-range
finalization, one-shot sealing, post-seal mutation rejection, by-value runtime
access, fixed-width overflow, allocation failure, malformed short allocation,
retryable cleanup, shallow-copy rejection for Building, Active, and
Cleanup_Failed owners with assertions enabled and disabled, inert destruction,
and tracked memory. Required adversarial lanes are
source-aware semantic parity, Odin ownership/safety, and structure/allocator
test-gap review.
