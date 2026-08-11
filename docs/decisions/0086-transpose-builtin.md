# Decision 0086: bounded `transpose` builtin

`transpose` consumes an array of arrays and emits an array of columns. Ragged
rows are padded with null, matching jq's observable behavior; empty input
returns an empty array. The result is newly allocated with owned child values.

Non-array diagnostics remain deferred. Syntax and program discriminants are
appended to preserve existing serialized forms. The focused evidence shard is
`compat/transpose.jq.test`.
