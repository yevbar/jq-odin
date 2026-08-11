# Decision 0114: bounded `toboolean`

The evaluator adds a zero-argument `toboolean` builtin. Boolean input is
copied unchanged; the exact strings `"true"` and `"false"` produce boolean
values. Invalid strings and other input kinds return the existing generic
numeric runtime error until jq-specific diagnostic contracts are assigned.
Dynamic and generator compositions remain outside this lane.

The focused oracle shard is `compat/toboolean-literal.jq.test`, with source
behavior anchored at `upstream/jq/tests/jq.test:701-705`.
