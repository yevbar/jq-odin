# Static numeric slice assignment

The parser, program lowering, evaluator, and value copy path cover the two
pinned jq assignment cases. Numeric bounds floor the start and ceil the end
before clamping; array replacement splices a cloned RHS array into a result.
String updates remain a catchable jq runtime error.

Oracle evidence: `upstream/jq/tests/jq.test:2437-2441`.
