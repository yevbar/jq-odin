# Decision 0110: bounded tonumber conversion

`tonumber` is represented as a zero-argument builtin. Numeric inputs are
cloned with their existing ownership; string inputs are parsed through the
existing literal-number constructor and become evaluator-owned numbers.
Invalid and unsupported input diagnostics remain on the existing runtime-error
path and are not expanded into a new continuation contract.
