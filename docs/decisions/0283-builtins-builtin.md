# Decision 0283: bounded `builtins/0` inventory

`builtins` is implemented as an operand-free evaluator builtin with an owned
array result. The inventory is sourced from the pinned jq oracle and is kept
ordered because jq exposes that order. This slice does not add dynamic builtin
dispatch; it only restores the inventory query itself.
