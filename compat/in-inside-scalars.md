# Scalar `inside` compatibility shard

This shard covers static scalar needles for `inside`, including numbers,
strings, null, and a non-match. jq defines `inside` through `contains`
(`upstream/jq/src/builtin.jq:183`); the evaluator's containment kernel already
handles scalar equality and string substrings. `in` remains restricted to
array/object containers because jq's `has` reports a typed error for scalar
containers. Dynamic arguments and richer generator forms remain deferred.
