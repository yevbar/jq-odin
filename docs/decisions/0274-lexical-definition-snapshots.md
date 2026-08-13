# Decision: retain lexical snapshots for redefined filter names

jq resolves a definition body in the lexical environment at its declaration.
For example, in `def f: .+1; def g: f; def f: .+100;`, `g` must continue to
call the first `f`, while a top-level `f` call uses the later definition.

The driver therefore retains every parsed definition and records a
`scope_end` declaration index. Expansion resolves the newest matching name and
arity at or before the current scope endpoint. This is a bounded correction to
textual module expansion; recursive calls still require evaluator activation
frames and are not inferred from this metadata.

Evidence: `upstream/jq/tests/jq.test:859-863` and
`compat/module-lexical-redefinition.jq.test`.
