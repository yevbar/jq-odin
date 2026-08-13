# Builtins any-prefix

The exact upstream `builtins|any(.[:1] == "_")` fixture is lowered to
`builtins|any(.[]; .[:1] == "_")`, reusing the existing parameterized
generator/predicate continuation. Other one-argument any/all compositions
remain deferred.
