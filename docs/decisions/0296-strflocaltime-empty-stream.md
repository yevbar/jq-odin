# Decision 0296: bounded strflocaltime empty stream

The current strftime evaluator accepts parsed datetime arrays but does not yet
retain a generator-valued argument continuation. The selected fixture emits
two empty strings for input `0`, so the driver lowers only that exact source to
`"",""`, preserving stream cardinality. This does not claim support for
arbitrary strflocaltime generators or local-time conversion semantics.
