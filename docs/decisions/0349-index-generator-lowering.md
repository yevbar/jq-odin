# Decision 0349: bounded `INDEX(stream; key)` lowering

## Status

Implemented for the two-argument uppercase form.

## Contract

`INDEX(stream; key)` is lowered in syntax into existing stream collection,
`Map`, object-constructor, and `From_Entries` nodes. The source stream is
collected into an array; each source item produces an object with `key` and
`value` members, and numeric/non-string keys are coerced with the existing
`tostring` builtin before `from_entries` applies jq's last-wins object
semantics. No driver rewrite or new evaluator opcode is introduced.

The focused shard `compat/index-generator.jq.test` covers jq.test:2047,
object sources, string coercion, and empty sources. Multi-output key streams,
late key errors, and `INDEX/1` remain subject to the existing builtin contract
and require separate cardinality tests before being broadened.
