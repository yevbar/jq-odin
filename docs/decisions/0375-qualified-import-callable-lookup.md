# Qualified imported callable lookup phase

## Decision

Add a source-only `module_callable_ref` lookup over the loader's collected
definition table. A complete qualified spelling such as `foo::a` resolves to a
borrowed namespace, local name, definition index, and arity without expanding
the body. The lookup is validated independently of evaluator dispatch.

## Evidence

The exact jq.test:1862 query is:

```jq
import "a" as foo; import "b" as bar; def fooa: foo::a; [fooa, bar::a, bar::b, foo::a]
```

With the pinned module fixtures, jq returns `["a","b","c","a"]`; the Odin
candidate still reports a filter parse error because imports are currently
stripped before syntax parsing. The existing fixture remains
`compat/module-directory-resolution.jq.test`.

## Boundary

This phase does not route execution. `module_definition` bodies remain owned
source strings, while `program.Callable_Entry` body indices refer to one
compiled Program graph. Routing an imported body requires parser input that
retains import directives, cross-source AST/program merging, and a driver-owned
compiled definition table; textual expansion remains the current fallback.

The lookup result borrows the definition table and must not outlive it. Invalid,
unqualified, unknown, and malformed references return `found = false` without
allocating or changing table ownership.
