# Decision 0325: bounded root iterator literal assignment

## Contract

The jq 1.8.1 cases at `upstream/jq/tests/jq.test:1289-1291` use `.[] = 1`.
For an array, every element is replaced in place; for an object, every value
is replaced while keys and order remain intact; empty containers remain empty;
non-iterable inputs raise jq's catchable `Cannot iterate over ...` diagnostic.

## Implementation

`Static_Iterator_Set_Number` is a dedicated syntax/program opcode, rather than
overloading object-field or literal `setpath` instructions. The parser accepts
only a root empty-field iterator (`.[]`) with a scalar literal RHS. The
compiler stores one owned literal operand. The evaluator validates the input
kind, clones/constructs each replacement under the existing allocator, and
updates array slots or object values copy-on-write before emitting exactly one
container result. No textual driver rewrite or general path-update ABI is
introduced.

## Limits and evidence

Generator-valued RHS, `|=`, compound operators, nested paths, and dynamic path
expressions remain deferred to the generic path-update contract in decision
0324. Focused coverage is recorded in `compat/iterator-assignment.jq.test`.
