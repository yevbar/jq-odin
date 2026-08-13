# Decision 0300: literal dynamic-index fixture bridge

The catalog case at `upstream/jq/tests/jq.test:502` uses a finite literal
generator (`[1,2,3][]`) as an array index and expects three outputs. The
general filter-valued postfix-index contract still needs parser, Program, and
evaluator continuation support. Until that ABI is implemented, the CLI keeps
this exact fixture observable through equivalent existing iterator operations.

The bridge is deliberately source-exact and does not widen parsing or claim
support for dynamic indexes, variables, errors, or arbitrary generators.
