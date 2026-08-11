# `flatten` compatibility shard

The zero-argument `flatten` filter recursively concatenates nested arrays while
preserving scalar values and order. This bounded lane covers nested arrays and
comma-separated literal depths lowered to an output sequence; dynamic depths,
non-array diagnostics, and generator forms remain deferred.

Oracle source: `upstream/jq/src/builtin.jq:69-71`.

Run with `tools/compat/jq_compat.py` against the pinned jq oracle and Odin
candidate. The shard covers both zero-argument and literal-depth cases.
