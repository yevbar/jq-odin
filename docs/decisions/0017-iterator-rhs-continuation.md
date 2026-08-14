# Decision 0017: resumable root iterator RHS updates

`.[] |= FILTER` is lowered to `Static_Iterator_Update`, a first-class AST and
program form whose one instruction operand is the compiled RHS filter. The
evaluator retains the root container and resumes a child frame per element.

The child stream uses jq's path-assignment cardinality: the first output
replaces the selected element, additional outputs are discarded, and an empty
stream deletes the element. Deletion is performed as an explicit resumable
phase so allocator failures can be retried without losing the input owner.

This slice intentionally covers root array/object value iterators. Nested path
updates and general multi-path assignment remain deferred until a shared path
continuation contract is recorded.
