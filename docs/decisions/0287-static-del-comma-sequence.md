# Decision 0287: lower static comma `del` paths as a sequence

The existing `Delpaths` program ABI accepts one literal path-array child. A
comma-separated `del(.a,.b)` is a stream of paths at the jq language level, but
the static subset can be represented exactly by sequentially applying one
existing `Delpaths` operation per path. The parser now performs that lowering
for static field/index paths. No evaluator, program, or ownership contract is
changed.

Slices, computed indexes, and generator-valued paths remain unsupported until
the general path continuation contract is implemented.
