# Decision 0069: bounded `keys_unsorted` builtin

Status: proposed on 2026-08-11.

`keys_unsorted` returns object names in insertion order. This operand-free lane
reuses the existing object-entry traversal and skips the sorting pass used by
`keys`; the focused oracle evidence is `compat/keys-unsorted.jq.test`.

Array and non-object semantics remain deferred. The implementation preserves
existing value ownership and introduces no continuation contract.
