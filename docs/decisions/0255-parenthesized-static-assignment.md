# Decision 0255: parenthesized static assignment

The existing bounded `.foo = scalar` assignment is accepted inside a
parenthesized `try (...) catch ...` expression. The parser unwraps transparent
`Parenthesized` nodes before validating the existing scalar RHS contract; no new
path or continuation representation is introduced. General dynamic assignment,
nested paths, and generator-valued RHS expressions remain deferred.

Evidence: `upstream/jq/tests/jq.test:213-229` exercises assignment failures
through `try (...) catch .`; `compat/static-field-set-try.jq.test` covers the
successful object-field subset.
