# Bounded object-literal `contains`

This shard covers shallow object-subset containment with literal object
needles, anchored to `upstream/jq/tests/jq.test:1623-1625`. The evaluator
checks that every literal needle key exists and its value is equal or
contained. Nested object/array needles, dynamic arguments, and non-object
diagnostics remain deferred; literal string containment remains covered by
`compat/contains-literal.jq.test`.
