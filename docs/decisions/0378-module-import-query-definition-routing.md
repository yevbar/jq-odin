# Module imports with query-local definitions

## Decision

When a filter begins with an `import` or `include` directive and also contains
query-local definitions, route it through the existing module loader. The loader
already collects the definitions, resolves aliases, expands qualified calls,
and materializes data imports; the parser/compiler/evaluator then receive the
expanded filter. Filters without a leading module directive retain the existing
real AST call-frame route.

This is a routing guard only: it adds no textual substitution or new namespace
ownership. It preserves the loader's existing data-over-code import precedence.

## Evidence

The exact jq.test:1862 and :1879 filters now pass through the real driver path:

```jq
import "a" as foo; import "b" as bar; def fooa: foo::a; [fooa, bar::a, bar::b, foo::a]
import "data" as $a; import "data" as $b; def f: {$a, $b}; f
```

Focused fixture: `compat/module-query-local-definitions.jq.test` (2/2).

## Source boundary

`src/driver/package.odin:1228-1262` chooses between direct syntax lowering and
`load_filter_modules`; `src/driver/module_loader.odin:2439-2627` owns import
collection, definition expansion, and data-reference materialization. The
existing namespace lookup contract remains borrowed and loader-owned.
