# `add(empty)` compatibility shard

This bounded lane accepts the literal empty generator as the child of `add`.
Because the child emits no values, jq returns `null`; arbitrary generator
children such as `add(range(3))`, dynamic arguments, and non-array diagnostics
remain deferred.

Evidence: jq defines `add` by reducing its input in `upstream/jq/src/builtin.jq:57`;
the empty-generator behavior is exercised by the pinned jq oracle.
