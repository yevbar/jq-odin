# Static path builtins

The first path slice represents `path(filter)`, `paths`, and
`getpath([literal components])` as explicit syntax nodes and program opcodes.
The evaluator keeps path arrays as owned `value.Value` arrays. `path(filter)`
is intentionally limited to statically addressable field/index filters;
`getpath` accepts literal arrays containing strings and numbers. Dynamic path
filters and mutations (`setpath`, `delpaths`, and assignment through arbitrary
generators) remain separate contracts because they require resumable path
collection and update semantics.

This keeps syntax independent of runtime values and preserves the package graph:
syntax owns source nodes, compiler/program own lowering, and eval owns path
array construction and lookup.
