# Decision 0072: bounded `to_entries` builtin

Status: proposed on 2026-08-11.

The jq `to_entries` filter converts an object into an array of `{key,value}`
records. This lane preserves insertion order and uses owned object/array
construction. The focused oracle evidence is `compat/to-entries.jq.test`.

Array and non-object semantics remain deferred; no continuation contract is
introduced.
