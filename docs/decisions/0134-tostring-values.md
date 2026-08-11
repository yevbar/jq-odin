# Decision 0134: serialize non-string values for `tostring`

The evaluator's `Tostring` opcode preserves string inputs and uses the
existing owned compact-JSON text helper for every other value. The helper's
result is transferred into an owned string value and its temporary allocation
is released. This evaluator-local change does not alter AST, program, or
package graph contracts.

Evidence: `upstream/jq/tests/jq.test:2148-2158` anchors scalar stringification;
`compat/tostring-values.jq.test` records null, boolean, number, array, object,
and string parity.
