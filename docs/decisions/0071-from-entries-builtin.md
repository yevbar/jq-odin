# Decision 0071: bounded `from_entries` builtin

Status: proposed on 2026-08-11.

The jq `from_entries` filter builds an object from an array of `{key,value}`
objects. This lane accepts that canonical shape, preserves array order, and
uses the existing owned object insertion API. The focused oracle evidence is
`compat/from-entries.jq.test`.

Alternate key spellings, malformed entries, duplicate-key edge cases, and
non-array diagnostics remain deferred.
