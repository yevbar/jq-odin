# Static slice assignment contract

The jq forms `.[start:end] = RHS` and `.[start:end] |= RHS` are not read-only
slice operations.  They require a dedicated AST/program operation that owns
the original array, evaluates the RHS with the original input, and constructs
a replacement array by copying the prefix, RHS stream, and suffix.  The
existing `Slice` opcode is a view-producing read operation and must not be
reused for mutation: its backing storage is shared and its bounds are clamped
for reads.  String targets must instead raise the catchable jq error
`Cannot update string slices`.

Upstream evidence: `upstream/jq/tests/jq.test:2437-2441`.

The implementation sequence is parser/AST shape, appended program opcode and
operand validation, an allocator-owned value splice helper, evaluator original
input/RHS continuation, and focused oracle tests for both string failure and
array replacement.  Until all layers exist, the parser must continue rejecting
slice assignment rather than emitting an incomplete instruction.
