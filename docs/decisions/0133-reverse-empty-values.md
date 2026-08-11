# Decision 0133: zero-length values reverse to an empty array

The evaluator's `Reverse` opcode now returns an allocated empty array for
null, numeric zero, an empty string, and an empty object, matching jq's
length/index behavior. Non-empty scalar and object inputs still report the
existing iterator error; array reversal is unchanged. No AST, program, or
package graph contracts change.

Evidence: `upstream/jq/tests/jq.test:2365-2369` anchors reverse behavior;
`compat/reverse-empty.jq.test` records direct oracle probes.
