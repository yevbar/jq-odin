# Decision 0239: preserve scalar values from `error(...)`

The Odin evaluator accepts static number, boolean, and null arguments to
`error(...)`. During `try`/`catch`, the typed scalar is carried through the
pending-value channel so the catch filter observes `0`, `false`, or `null`
rather than a diagnostic string. For an uncaught error the runtime key is the
compact JSON rendering, matching jq's visible diagnostic behavior.

Object, array, and dynamic error arguments remain unsupported until a shared
value-evaluation contract is available. This lane does not change continuation
frames or number formatting.
