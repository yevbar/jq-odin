# Decision: bounded filter-parameter call slice

The existing module expansion path is sufficient for a nonrecursive filter
parameter definition and literal call. `def f(a): a + . + 11; f(20)` expands
before syntax lowering and evaluates to `51`, matching jq 1.8.1.

This does not establish general callable semantics: recursive calls,
parameterized generators, and dynamic call arguments still require resumable
evaluator call frames. Keep those out of this bounded slice.

Evidence: `src/driver/module_loader.odin:667-712` validates filter-parameter
bodies through a temporary identity filter, while
`src/driver/module_loader.odin:1729-1998` performs bounded textual expansion and
argument substitution.
