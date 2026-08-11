# Decision 0067: bounded ASCII case builtins

The zero-argument ascii_downcase and ascii_upcase filters accept strings and
change only ASCII letters. Non-ASCII UTF-8 bytes pass through unchanged.
Non-string diagnostics and locale-sensitive behavior remain deferred.

Syntax and program discriminants are appended to preserve existing serialized
forms; the focused evidence shard is compat/ascii-case.jq.test.
