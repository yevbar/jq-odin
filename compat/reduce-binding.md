# Reducer binding/update form

This shard covers the static reducer shape where the initial expression is a
literal binding (`4 as $else | $else`) and the update binds the accumulator
before adding the product of the input item and accumulator. Dynamic reducer
expressions and destructuring remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:2247-2249`.
