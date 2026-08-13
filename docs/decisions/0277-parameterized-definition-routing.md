# Parameterized definition routing

Status: implemented bridge slice

The parser/Program vertical slice supports only zero-argument definitions.
Single parameterized definitions therefore route through the existing module
expander, which substitutes filter-valued arguments with grouping and binds
`$` value parameters without changing caller scope. The driver detects a
parameter list before the definition colon; multiple definitions continue to
use the loader for declaration-time visibility.

Evidence: `src/driver/package.odin:613-637`; focused compatibility shard
`compat/parameterized-definition-call.jq.test` passes 3/3 against pinned jq,
covering `upstream/jq/tests/jq.test:785-787,851-856,868-871`.

This deliberately does not claim first-class parameterized evaluator frames;
closures and recursive parameterized definitions remain deferred to the
definition-table/call-frame contract.
