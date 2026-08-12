# Decision 0250: bounded zero-catch `try`

The parser now accepts jq's `try EXP` form by materializing an existing
`empty` catch branch. This avoids changing evaluator frame ownership or the
`Try` program contract. The bounded shard covers static errors and comma-stream
composition. Defined-or (`//`) compilation and dynamic catch expressions are
deferred because they require separate compiler/evaluator contracts.
