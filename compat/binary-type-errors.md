# Binary type-error messages

This shard covers the literal string subtraction and string-plus-container
errors exercised by `upstream/jq/tests/jq.test:1963` and `:1992-1996`.
The evaluator now retains a bounded jq-style operand rendering through
`try ... catch .`; unrelated binary diagnostics remain deferred.
