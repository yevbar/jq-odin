# Multi-seed foreach

The focused cases pin jq's `foreach EXP as $name (INIT; UPDATE)` behavior when
`INIT` is a comma stream: each seed is replayed over all generator values, and
the resulting accumulators are emitted in seed-major order. The cases come
from `upstream/jq/tests/jq.test:2496-2503`.

The Odin slice intentionally accepts literal numeric seeds, literal comma
streams, `.[]` or `range(n)` generators, and the update forms `$name` and
`. + $name`. Other foreach filters still require the general continuation
contract.
