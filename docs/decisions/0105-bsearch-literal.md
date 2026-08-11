# Decision 0105: single-literal numeric `bsearch`

Append a `Bsearch` AST/opcode form for one numeric literal needle. The
evaluator performs ownership-safe binary search over an input array and emits
the matching index or `-(insertion_index + 1)`, matching jq's numeric search
contract. Multi-needle generators, object ordering, dynamic arguments, and
non-array diagnostics remain deferred from the cluster at
`upstream/jq/tests/jq.test:1789-1801`.
