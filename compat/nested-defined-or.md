# Nested defined-or over a multi-output iterator

This shard covers `//` inside an array constructor whose left operand is a
multi-output field iterator. Null/false outputs are suppressed; defined values
pass through, and an entirely empty iterator uses the fallback once.
