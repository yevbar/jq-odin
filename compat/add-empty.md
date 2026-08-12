# `add(empty)` compatibility shard

This lane accepts literal `empty` and numeric `range` generators as the child
of `add`. Empty streams return `null`; emitted values are reduced in order.
Dynamic arguments and non-array diagnostics remain deferred.

Evidence: jq defines `add` by reducing its input in `upstream/jq/src/builtin.jq:57`;
the empty-generator behavior is exercised by the pinned jq oracle.
