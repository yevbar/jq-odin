# `acosh` compatibility shard

This shard covers jq's zero-argument `acosh` filter for boundary, ordinary,
and out-of-domain numeric inputs. The evaluator delegates to Odin's native
`math.acosh_f64` implementation. The oracle behavior is defined by
`upstream/jq/src/builtin.jq` and the corresponding jq tests.
