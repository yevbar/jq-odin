# Bounded object-literal `contains`

This shard covers object-subset containment with literal object needles,
including nested arrays, anchored to `upstream/jq/tests/jq.test:1623-1625`.
Array needles cover literal subset matching as a focused regression. Dynamic
arguments and exact non-object diagnostic wording remain deferred; literal
string containment remains covered by `compat/contains-literal.jq.test`.
