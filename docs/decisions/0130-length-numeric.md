# Decision 0130: numeric `length` returns magnitude

The evaluator's `Length` opcode now handles number inputs by returning their
absolute value, matching jq. Null, arrays, objects, and strings retain their
existing branches; booleans and unsupported values still report the existing
length misuse. This evaluator-local change does not alter AST, program, or
package graph contracts.

Evidence: `upstream/jq/tests/jq.test:728-732` anchors existing length cases;
`compat/length-numeric.jq.test` records direct numeric oracle probes.
