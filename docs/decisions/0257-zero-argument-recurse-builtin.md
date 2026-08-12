# Decision 0257: zero-argument `recurse` builtin

The parser recognizes the zero-argument identifier `recurse` as the existing
operand-free `Recurse` node/opcode used by standalone `..`. jq defines this
named builtin as the same preorder recursive descent (`recurse(.[]?)`), so
sharing the evaluator's explicit frame traversal preserves output ordering and
cardinality without adding a second continuation contract. Calls with an
explicit argument remain outside this bounded implementation.

The focused compatibility shard is `compat/recurse-builtin.jq.test`; the
observable definition is in `upstream/jq/src/builtin.jq:36-39`.
