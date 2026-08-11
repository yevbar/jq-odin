# `empty` compatibility shard

This shard covers the zero-argument `empty` generator. It yields no output;
when composed with a comma stream, only the other branch is observed.

Evidence: jq's `empty` behavior is exercised by the focused cases in
`compat/empty.jq.test:1-7`. Diagnostic forms and generator composition beyond
the basic comma case remain deferred.
