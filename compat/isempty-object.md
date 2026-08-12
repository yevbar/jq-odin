# `isempty` literal objects

The bounded `isempty` evaluator now recognizes literal object children as
value-producing filters, matching jq's `isempty({}) == false` behavior. Dynamic
object expressions and generator-valued children remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:2097-2101` and
`upstream/jq/src/builtin.jq:187`.
