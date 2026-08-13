# `modulemeta` runtime context boundary

The selected jq cases 1931, 1935, and 1939 exercise `modulemeta` with input
`"c"`. jq loads the named module and returns an object containing its constant
metadata, direct dependency descriptors, and defined function names. The
current Odin loader parses module directives and definitions while expanding a
filter, but `Module_Outcome` retains only data-import and rewrite flags; the
dependency and definition records are destroyed before evaluator execution.
The evaluator has no module search-path or module-table context and therefore
cannot implement `modulemeta` as an ordinary operand-free builtin.

The required contract is:

1. module loading owns a stable metadata table for the current invocation;
2. `Compiled_Filter`/`Run_Result` retain that table through all input values;
3. a `modulemeta` instruction resolves its string input through the table and
   emits an owned object containing `deps` and `defs` in jq order;
4. cleanup releases the metadata table exactly once, including preparation and
   shared-compilation paths.

A driver rewrite for the literal `modulemeta` fixture would hard-code the
module name and bypass runtime resolution, so it is intentionally rejected.
The next implementation should add the metadata table at the driver/module
boundary before adding syntax/program/evaluator lowering.
