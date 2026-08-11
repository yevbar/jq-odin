# Decision 0117: quoted-field postfix chaining

The parser converts a non-interpolated quoted string following a postfix dot
into a shorthand Field node carrying parser-owned decoded text. This permits
`."foo"."bar"` and mixed `.foo."bar"` chains without adding a new program
opcode or evaluator ownership path. Interpolated strings and dynamic field
names remain deferred.

Evidence: `upstream/jq/tests/jq.test:168-169` and
`compat/quoted-field-postfix.jq.test` against the pinned jq oracle.
