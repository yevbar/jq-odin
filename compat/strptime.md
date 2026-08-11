# `strptime`

This bounded shard supports literal ISO-8601 formats `%Y-%m-%dT%H:%M:%SZ`
and `%FT%T`, returning jq's parsed datetime array including weekday and
zero-based day-of-year fields. Other format directives and malformed-input
diagnostics remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:1847-1851`.
