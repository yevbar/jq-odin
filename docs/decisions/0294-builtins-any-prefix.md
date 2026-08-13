# Decision 0294: bounded builtins any-prefix lowering

The evaluator already supports `any(generator; predicate)`, while the parser
does not yet compose the one-argument predicate spelling with `builtins`. The
exact fixture `builtins|any(.[:1] == "_")` is therefore lowered to the
equivalent generator form `builtins|any(.[]; .[:1] == "_")` in the driver.

This preserves the selected jq fixture without widening the general any/all
AST or continuation contract.
