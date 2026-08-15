# Decision 0401: nested lexical formal-call ABI

## Scope

The jq.test:864 query combines nested parameterized definitions, shadowing
`$x` bindings, and a filter-valued argument whose bare formal (`x`) resolves
to the enclosing definition:

```jq
def id(x):x; 2000 as $x | def f(x):1 as $x | id([$x, x, x]);
def g(x): 100 as $x | f($x,$x+x); g($x)
```

The driver now routes nested parameterized definitions through the syntax /
Program call graph instead of textual module expansion. Evaluator call frames
propagate retained formal argument edges through constructor and binary
continuations. Parameter references inside a retained argument skip the
current formal scope and resolve the enclosing formal edge; ordinary variables
continue to resolve the caller's lexical bindings. Callee body edges are not
followed during parameter-reference discovery, preserving recursion bounds.

Evidence: `upstream/jq/tests/jq.test:864`,
`compat/nested-lexical-call.jq.test`.
