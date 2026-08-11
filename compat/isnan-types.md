# `isnan` type semantics compatibility shard

This shard covers jq's type-independent `isnan` predicate: non-number inputs
yield `false`, while NaN yields `true` and finite numbers yield `false`.

Evidence: `upstream/jq/tests/jq.test:693-694` anchors numeric NaN checks; the
new fixture records direct oracle probes for null, booleans, strings, arrays,
objects, NaN, and a finite number.
