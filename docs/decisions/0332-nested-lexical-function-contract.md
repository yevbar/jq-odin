# Decision 0332: nested lexical function-definition contract

Status: contract and oracle shard; implementation follows the shared
syntax/program/evaluator call-frame lane.

The four focused probes in `compat/nested-definition-calls.jq.test` exercise
semantics that the current top-level zero-argument definition slice does not
represent: local definitions nested in a definition body (`jq.test:775`),
declaration-time snapshots through redefinition and nested array expressions
(`jq.test:789`), parameterized calls with independent lexical variables
(`jq.test:864`), and generator backtracking through nested calls (`jq.test:875`).

## Contract

1. **Syntax** emits a `Definition` binding whenever `def name [ (params) ] :
   Query ;` occurs in a `Query`, not only at the parse root. The node owns its
   name/parameter spans, body root, and declaration ordinal. A call records
   name, arity, argument roots, and the lexical definition scope in which it
   was parsed; it never substitutes source text.
2. **Program/compiler** lowers each definition body exactly once into an
   immutable definition entry keyed by `(name, arity, ordinal)`. A call operand
   resolves to the entry visible at its declaration point. Nested definitions
   therefore produce child lexical scopes; later redefinitions do not rewrite
   earlier bodies. Definition entries own all text and instruction storage.
3. **Evaluator** activates an explicit call frame containing caller resume
   state, callee entry, lexical parent/binding frame, argument continuation
   state, and recursion depth. Callee outputs stream through the ordinary
   iterator protocol; callee exhaustion pops one frame and resumes the exact
   caller continuation. `empty`, errors, and `try/catch` must unwind this frame
   without host-language recursion.

The minimum first implementation slice is zero-argument nested definitions
with declaration-time lookup and generator returns (775/789/875). Parameter
closures and `$`-bindings in 864 follow once argument roots and binding frames
are represented in the same ABI. Recursive calls must use the same activation
path and an explicit depth/resource policy.

## Upstream evidence

- jq's grammar makes `FuncDef Query` a right-scoped query production, so a
  definition can occur at every query nesting level and binds the following
  query (`upstream/jq/src/parser.y:324-345`).
- Both zero-argument and parameterized definitions compile from a `Query` body
  (`upstream/jq/src/parser.y:475-492`); `gen_function` turns regular parameters
  into formal closures and binds them into the body (`upstream/jq/src/compile.c:548-567`).
- The compiler recursively binds call references inside nested closures and
  argument lists (`upstream/jq/src/compile.c:306-344`) and emits relative
  lexical-parent levels for calls and closure arguments
  (`upstream/jq/src/compile.c:1080-1088,1306-1317`). Runtime closure creation
  then captures the referenced frame/bytecode pair
  (`upstream/jq/src/execute.c:110-131`).
- Runtime `CALL_JQ` pushes a frame carrying the callee closure, argument
  closures, return address, and return stack state; `RET` pops exactly one
  frame before resuming the caller (`upstream/jq/src/execute.c:934-987`).

The existing driver/module-loader expansion remains a compatibility bridge for
simple non-recursive module cases. It must not be extended to claim this
contract: textual expansion loses declaration ordinals, lexical parent
identity, and resumable generator state.
