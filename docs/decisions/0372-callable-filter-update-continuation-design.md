# Decision 0372: callable filter-update continuation design

## Status

Accepted design boundary; implementation deferred until the continuation can
be landed with the complete stream and ownership contract.

## Evidence

The jq fixture `upstream/jq/tests/jq.test:1236-1238` evaluates
`def inc(x): x |= .+1; inc(.[].a)` and updates each selected field while
preserving the containing array and object. jq's VM saves the caller path,
root value, and program counter around `PATH_BEGIN`/`PATH_END`
(`upstream/jq/src/execute.c:629-672`), then backtracks through path and RHS
streams. A scalar argument ABI cannot represent this behavior: evaluating
`.[].a` before entering `inc` loses both the selected coordinates and the
caller root.

## Chosen continuation contract

The next implementation must add a first-class `Parameter_Filter_Update` AST
node and append-only program opcode with explicit operands for:

1. the callable argument filter instruction;
2. the update RHS filter instruction; and
3. a bounded path/update mode (identity, then numeric-add) validated by the
   compiler rather than inferred from source text.

The Call frame retains an owned clone of the caller root and borrows immutable
instruction metadata from the sealed Program. Its explicit phases are:

`Argument_Path_Start → Argument_Path_Active → RHS_Start → RHS_Active →
Apply_Path → Emit_Result → Resume_Argument`.

`Argument_Path_Active` evaluates the argument against the retained root and
materializes each path as an owned path vector. `RHS_Active` evaluates the RHS
against the selected value for each path, retaining only the first result and
recording empty/error/cardinality state. `Apply_Path` performs copy-on-write
from the original root coordinates, never from a previously mutated output.
After one result is emitted, `Resume_Argument` resumes the argument generator;
it must not replay a completed scalar argument or duplicate outputs. All path,
selected-value, RHS, and pending-output values are frame-owned and destroyed on
every completion, error, or cancellation path. Program text and instruction
edges remain borrowed and are invalid after Program retirement.

The first executable milestone may restrict the argument to a literal field
and RHS to identity or numeric-add, but it must use these continuation fields
and preserve root/path state. Generator arguments such as `inc(.[].a)` should
only be enabled after the same phases pass dedicated stream tests.

## Rejected alternatives

- Textual expansion or scalar substitution: loses path coordinates, root
  ownership, empty behavior, and typed errors.
- Reusing ordinary two-edge Call argument activation: it materializes values
  before the callee and cannot resume path capture.
- A numeric-only opcode without RHS/path continuation: cannot generalize to
  jq's many-output and error ordering and would repeat the failed partial
  extension recorded in decision 0368.

## Required validation

Before implementation is accepted, compare pinned jq and Odin for literal
`inc(.a)` across missing/null/object/scalar roots, then generator
`inc(.[].a)` across zero/one/many paths, overlapping paths, RHS empty,
multi-output RHS, and late errors. Require package checks, evaluator/driver
tests, a focused compatibility fixture, and independent semantic plus
ownership adversarial review.
