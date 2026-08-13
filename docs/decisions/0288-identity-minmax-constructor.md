# Decision 0288: identity-key min/max lowering

For the exact constructor `[min,max,min_by(.),max_by(.)]`, identity-key
extrema are equivalent to `[min,max,min,max]`. This is a semantics-preserving
driver rewrite using existing program instructions; arbitrary `min_by` and
`max_by` filters still require a key-stream contract.
