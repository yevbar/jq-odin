# Root iterator defined-or update fixture

Pinned jq 1.8.1 behavior for `.[] //= RHS`:

- only `null` and `false` selected values run the RHS; truthy values remain
  unchanged;
- the RHS sees the original root input, so `.[0]` reads the source array's
  first element rather than the selected element;
- every RHS output emits an independent root (including when all selected
  values are already truthy); an empty RHS emits no root.

The Odin compiler uses the existing `Static_Iterator_Update` instruction with
an explicit defined-or marker. The evaluator snapshots the root input once,
runs the child RHS against that snapshot exactly once, and rebuilds one root
per RHS output by applying that output to every null/false selected value.
Ownership follows the iterator continuation contract: each rebuilt root owns
its replacements independently and the snapshot remains parent-owned until
teardown. Unlike `|=`, the child is not canceled after its first output.
