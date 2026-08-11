# Decision 0096: contain literal error boundary

The bounded `contains` form accepts one literal string argument. If the
argument is a non-string literal, reject the filter through the parser's
lookahead-aware error path after consuming the closing parenthesis. This is a
controlled parse failure (`rc=3`) instead of an assertion when lookahead is
end-of-input. Array/object recursive containment remains deferred.

The regression cases are `contains([2])` and `contains({"a":1})` in
`src/syntax/parser_test.odin`. Accepted string literals continue to use the
existing compatibility shard in `compat/contains-literal.jq.test`.
