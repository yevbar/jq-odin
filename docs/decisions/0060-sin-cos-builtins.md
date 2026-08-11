# Decision 0060: bounded scalar sine and cosine builtins

The zero-argument sin and cos filters accept numbers and return the
corresponding scalar trigonometric result. Non-number diagnostics,
special-value handling, and jq's complete math compatibility remain deferred.

Syntax and program discriminants are appended to preserve serialized forms;
the focused evidence shard is compat/trig.jq.test.
