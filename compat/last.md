# `last` compatibility shard

This bounded zero-argument lane implements jq's `last` array selector for
non-empty, empty, and null inputs. Generator forms (`last(generator)`) and
exact diagnostics for string/number inputs remain deferred.

Evidence: jq's definition is `def last: .[-1];` in
`upstream/jq/src/builtin.jq:167`; `compat/last.jq.test` records direct oracle
cases.
