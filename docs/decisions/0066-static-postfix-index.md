# Decision 0066: bounded static postfix indexing

## Context

jq uses bracket postfixes both for array lookup and for path composition. The
first useful compatibility slice is `.[N]` and `.field[N]` where `N` is a
non-negative integer literal. This covers ordinary read-only lookup without
pretending that Odin's array indexing is equivalent to jq path assignment.

## Contract

The syntax node owns the numeric spelling until compiler lowering. The program
stores the child instruction followed by an owned text operand. The evaluator
resumes the child stream, then evaluates the index once for each child output;
out-of-range and null inputs yield jq's null result. Values copied from arrays
are independently owned according to `docs/contracts/ownership.md`.

Negative/fractional/dynamic indexes, slices, and all assignment operators are
deferred because they require additional parser and path-update contracts.

## Evidence and validation

- `upstream/jq/tests/jq.test:164-180,283-287`
- `compat/postfix-index.jq.test` passes against the pinned jq oracle.
- Odin package checks and focused evaluator tests pass on the implementation
  branch.
