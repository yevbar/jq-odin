# Decision 0397: bounded binding-aware path assignment

The evaluator now supports the exact unused-binding form
`(.a as $x | .b) = literal`. The producer path is evaluated first so jq's
typed array/number diagnostics are preserved; the body field is then applied
to the original root with the existing copy-on-write path setter. Null roots
materialize an object, matching jq.

This is intentionally bounded to a three-operand `Binding` with static field
producer/body paths and a literal RHS. Binding references in the RHS, dynamic
body paths, multi-output producers, and filter-valued path bodies remain
deferred until a general Binding_Path_Assign continuation exists.

Relevant implementation seam: `src/eval/evaluator.odin` Binding_Path_Assign
dispatch, static path materialization, `lookup_path`, and `set_path_value`.
The focused fixture is `compat/binding-path-assignment.jq.test`.
