# Decision 0267: computed object keys consume postfix generator streams

An object constructor key expression such as `(.[])` is a jq filter, not a
single scalar lookup. During constructor setup, collect its child stream and
flatten each array/object result for the empty-field postfix. The resulting
owned key stream is paired with each value stream by the constructor's normal
Cartesian emitter, preserving jq's order and duplicate-key overwrite rules.

Evidence: `upstream/jq/tests/jq.test:766-768` and the dictionary-construction
forms at `upstream/jq/tests/jq.test:123-143`.
