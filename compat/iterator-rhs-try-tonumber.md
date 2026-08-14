# Iterator RHS continuation fixture

Pinned jq 1.8.1 behavior for `.[] |= try tonumber`:

- the RHS runs with each selected element as its input;
- the first RHS output replaces the element (later outputs are ignored by jq's
  path assignment semantics);
- an empty RHS stream deletes that element and resumes without skipping the
  shifted successor;
- object value iterators preserve keys while deleting entries whose RHS is
  empty.

The Odin evaluator represents the update as a first-class program instruction
with an explicit frame phase for the element cursor, child RHS continuation,
and deletion retry. No textual rewrite is involved.
