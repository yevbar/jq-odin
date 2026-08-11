# Decision 0165: bind the right side of a pipe

## Scope

When parsing `input | expr as $name | body`, construct the `Binding` node for
`expr` and attach it as the pipe's right child. Do not wrap the entire pipe in
the binding. This preserves jq's input semantics and allows the binding body
to consume all outputs of the piped expression.

## Evidence

The focused `compat/binding-pipe.jq.test` shard compares a nested array
Cartesian equality stream against pinned jq 1.8.1. The parser unit test checks
the resulting `Pipe`/`Binding` shape.

## Deferred

Dynamic assignment, destructuring bindings, and broader generator/control-flow
forms remain deferred.
