# Decision 0334: null-base static deletion is a no-op

The bounded static `del` lowering already routes field and numeric-index paths
through `delete_path_value`. jq treats a missing path rooted at `null` as a
no-op: `del(.foo)`, `del(.[0])`, and `del(.foo[0])` each return `null` for a
`null` input. The evaluator now checks for a null base before component
dispatch and clones it unchanged.

Evidence: `upstream/jq/tests/jq.test:1168-1175` exercises static deletion
composition; direct jq 1.8.1 probes for the three paths above return `null`.
Focused coverage is in `compat/static-del-null.jq.test`.

This does not add dynamic path, generator-valued deletion, or non-null scalar
coercion. Non-null container/scalar diagnostics remain at the pre-existing
`d5856009` boundary; extending those cases to typed deletion errors is a
separate evaluator contract.
