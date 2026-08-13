# Decision 0263: bound literal path arrays

The existing path builtins accept literal array filters and already own their
path components as `value.Value` arrays. This slice extends that contract to a
lexical variable whose binding value is such an array, for example
`["foo",1] as $p | getpath($p)` and `setpath($p; 20)`.

The evaluator resolves a `Variable` through the existing binding-frame lookup,
requires the resolved value to be an array, and clones it before lookup or
copy-on-write update. This keeps ownership explicit: binding frames retain
their values while path operations consume only independent clones.

The scope deliberately excludes computed path expressions, generator-valued
bindings, and assignment/update operators. Those require a general resumable
path continuation contract. Missing object members remain jq `null` results,
including through a bound path.
