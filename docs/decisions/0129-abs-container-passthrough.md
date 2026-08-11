# Decision 0129: preserve containers for `abs`

The evaluator's `Abs` opcode now clones array and object inputs unchanged,
matching jq's type-directed behavior. Strings already used this identity path;
`Fabs` and all non-number/non-string `Abs` inputs retain their numeric error
behavior. This is evaluator-local and does not alter the AST, program, or
package graph contracts.

Evidence: `upstream/jq/tests/jq.test:2212-2229` covers the `abs` family; the
new `compat/abs-containers.jq.test` records direct oracle probes for arrays,
objects, strings, and numbers.
