# Decision 0268: Preserve identity continuations in bounded dynamic paths

The evaluator's dynamic `path` implementation now recognizes a `Sequence`
whose left side is the supported wildcard path (`.[]` or `.foo[]`) and whose
right side is identity. It reuses the wildcard path expansion, preserving
all generated array/object paths without guessing the behavior of arbitrary
filters.

The behavior is anchored to jq 1.8.1's generator-shaped path cases at
`upstream/jq/tests/jq.test:1101-1108`; predicate continuations such as
`select(.>3)` remain explicitly unsupported until evaluator continuation state
can retain and resume child filter streams.
