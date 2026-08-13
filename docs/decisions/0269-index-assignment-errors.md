# Numeric index assignment uses typed runtime errors

Static numeric path assignment remains a bounded evaluator opcode. The
evaluator accepts `null` as an empty-array base, matching jq's `.[0] = value`
coercion and preserving array extension. Non-array inputs produce typed
`User_Error` values (`Cannot index <kind> with number`) through the existing
`raise_runtime` transport. Array bounds errors from `value.array_set_take` are
translated to jq's `Out of bounds negative array index` and `Array index too
large` messages, which makes them catchable without introducing a new
continuation or shared program contract.

Evidence: `upstream/jq/tests/jq.test:229-232` and focused oracle probes for
null, array, object, number, string, and boolean inputs.
