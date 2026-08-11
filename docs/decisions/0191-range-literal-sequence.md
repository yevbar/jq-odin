# Decision 0191: bounded literal `range` sequences

The parser accepts comma-separated one-argument numeric literal generators in
`range`, such as `range(3,5)`. Each literal is lowered to the existing
iterator-backed `Range` opcode and composed with the existing comma sequence,
so output cardinality and ownership remain unchanged. Dynamic arguments,
semicolon forms beyond the existing bounded implementation, and continuation
forms remain deferred.

Evidence: `upstream/jq/tests/jq.test:435-437` exercises the literal sequence
`[range(3,5)]` and expects `[0,1,2,0,1,2,3,4]`.
