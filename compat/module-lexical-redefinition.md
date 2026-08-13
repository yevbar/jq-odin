# Lexical module-definition snapshots

`def g: f` resolves `f` as it existed when `g` was declared; a later
top-level redefinition of `f` must not rewrite `g`'s body. The driver now keeps
all definitions and records each declaration's lexical visibility endpoint.
