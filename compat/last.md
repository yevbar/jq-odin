# `last` compatibility shard

This bounded zero-argument lane implements jq's `last` array selector for
non-empty, empty, and null inputs. The bounded generator form
(`last(generator)`) consumes the complete child stream and returns its final
output, or null for an empty stream. Broader dynamic/control forms and exact
diagnostics for string/number inputs remain deferred.

Evidence: jq's definition is `def last: .[-1];` in
`upstream/jq/src/builtin.jq:167`; generator behavior is covered by
`upstream/jq/tests/jq.test:397-410`.
