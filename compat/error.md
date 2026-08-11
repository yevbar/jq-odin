# `error("literal")` compatibility shard

The shard checks a static string error's non-zero status, empty stdout, and
exact `jq: error (at <stdin>:1): foo` diagnostic. Evaluator-level tests also
verify that an optional parent suppresses the runtime error while retaining and
releasing the owned message. jq's `try`/`catch` parser syntax, dynamic error
arguments, numeric/non-string arguments, `halt`, and `debug` remain deferred;
the optional suppression test covers the existing continuation boundary.
