# Iterator-error catch values

The evaluator retains jq's typed `Cannot iterate over <kind> (<value>)`
message as the caught string value. Postfix `?` on `.a[]?` and `.a.[]?`
instead turns the same scalar iteration failure into an empty stream. The
focused fixture also keeps ordinary `try` branches adjacent to optional
branches inside one `map` argument, exercising jq's comma-separated `Query`
argument without adding a new evaluator continuation.

Oracle evidence: `upstream/jq/tests/jq.test:199-202`; the grammar gives every
function argument a complete `Query` at `upstream/jq/src/parser.y:745-756` and
distinguishes `EACH_OPT` at `upstream/jq/src/parser.y:610-620`.
