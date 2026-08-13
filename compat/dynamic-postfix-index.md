# Dynamic postfix index

This shard covers filter-valued postfix index keys. A key filter is evaluated
against the original input for each base result, and every integral numeric key
is applied in generator order. Empty key generators produce no output.

The behavior is specified by `upstream/jq/src/parser.y:175-181` and
`upstream/jq/src/jv_aux.c:80-87,130-154`.
