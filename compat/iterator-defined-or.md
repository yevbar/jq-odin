# Root iterator defined-or update fixture

Pinned jq 1.8.1 behavior for `.[] //= RHS`:

- only `null` and `false` selected values run the RHS; truthy values remain
  unchanged;
- the RHS sees the original root input, so `.[0]` reads the source array's
  first element rather than the selected element;
- first-output cardinality is retained and later RHS outputs are discarded.

The Odin compiler uses the existing `Static_Iterator_Update` instruction with
an explicit defined-or marker. The evaluator snapshots the root input once,
tests each selected value, and runs the child RHS against that snapshot only
when the value is null or false. Ownership follows the iterator continuation
contract: skipped values are destroyed immediately and the snapshot remains
owned by the parent frame until teardown.
