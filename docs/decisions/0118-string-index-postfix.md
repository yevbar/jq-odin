# Decision 0118: literal string bracket postfixes

The parser accepts a non-interpolated JSON string between `[` and `]` in a
postfix position and emits the existing shorthand Field node with parser-owned
decoded text. This keeps `.["foo"].bar` on the established Field evaluator path
without introducing an index-string runtime opcode. Dynamic/interpolated keys
and update semantics remain deferred.

Evidence: `upstream/jq/tests/jq.test:164-166` and
`compat/string-index-postfix.jq.test` against the pinned jq oracle.
