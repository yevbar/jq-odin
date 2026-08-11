# Quoted-field postfix chaining

This shard covers non-interpolated quoted field postfixes such as
`."foo"."bar"` and `.foo."bar"`, plus jq's null result for a missing quoted
field. It is anchored to `upstream/jq/tests/jq.test:168-169` and reuses the
existing shorthand Field compiler/evaluator contract. Interpolated quoted
fields, dynamic keys, and assignment/update forms remain deferred.
