# Filter-parameter definition and call

This shard covers a bounded, nonrecursive parameterized definition whose filter
argument is a literal. The module loader expands the call before parsing the
caller, preserving the caller input for `.` and substituting `a` with `20`.

The pinned jq 1.8.1 oracle emits `51` for:

```jq
def f(a): a + . + 11; f(20)
```

This is intentionally limited to one nonrecursive call; recursive definitions
require evaluator call frames and are not implied by this slice.
