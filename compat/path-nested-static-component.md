# Nested static path component

The driver lowers the exact `path(.a[path(.b)[0]])` form to
`path(["a","b"])`. Both path components are static field names; arbitrary
dynamic path filters remain evaluator work.
