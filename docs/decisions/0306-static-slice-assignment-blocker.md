# Static slice assignment blocker

Status: investigation recorded (2026-08-13)

The remaining jq cases at `upstream/jq/tests/jq.test:2437` and `:2441` use
`.[1.5:3.5] = RHS`. The value layer already provides
`array_replace_range_copy`, but the current evaluator's `Slice` contract is a
read-only child continuation: it retains one input frame and emits a sliced
value. Assignment needs a distinct four-operand instruction containing start,
end, base, and RHS, plus a continuation that evaluates RHS generators while
retaining the original input and then performs copy-on-write replacement.

A parser/IR-only prototype was intentionally reverted after `make
check-packages` reached the missing evaluator dispatch. This is not a safe
parser-only or driver rewrite: accepting the syntax without the evaluator
frame would create an invalid program contract. The next implementation VM
must own the complete syntax → program → evaluator → value slice, with focused
oracle checks for both the string error (`Cannot update string slices`) and
array replacement output before integration.
