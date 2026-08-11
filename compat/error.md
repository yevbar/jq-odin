# `error("literal")` compatibility shard

The shard checks a static string error's non-zero status, empty stdout, and
exact `jq: error (at <stdin>:1): foo` diagnostic, plus literal `try`/`catch`
forms where the catch receives the owned message. Dynamic error arguments,
numeric/non-string arguments, `halt`, and `debug` remain deferred.
