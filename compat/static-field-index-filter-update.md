# Nested static index filter update

This shard adds the bounded one-level `.name[index] |= FILTER` path update.
The parser/program carry a field name, non-negative static index, and RHS
instruction. The evaluator runs the RHS against the selected array element,
commits only the first output, cancels later outputs, and deletes an existing
element when the RHS is empty. Missing/null field intermediates synthesize an
array only when the RHS produces a value; empty updates preserve the missing or
null intermediate. Scalar field intermediates retain jq's typed index error.

Deeper paths, slices, and dynamic indexes remain outside this contract.
