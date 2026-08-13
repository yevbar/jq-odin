# Pick last error

The exact upstream error-only form `try pick(last) catch .` is lowered to an
equivalent catchable error. General `pick(last)` and path-valued pick forms
remain deferred to the path continuation contract.
