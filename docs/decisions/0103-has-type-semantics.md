# Decision 0103: literal `has` type and index semantics

The literal `has` follow-up now truncates positive fractional array indexes
(`has(1.5)` checks index 1), and wrong container/key combinations raise the
existing evaluator runtime error instead of silently returning false. Null
arguments are admitted through the literal parser and reach that runtime
boundary. This matches the jq probes around
`upstream/jq/tests/jq.test:1687-1695`.

Negative numeric arguments remain parser-deferred because the current shared
program contract does not lower unary-negation nodes; they must not be
silently reinterpreted as positive indexes. Dynamic arguments and recursive
map/path compositions remain outside this lane.
