# `flatten` compatibility shard

The zero-argument `flatten` filter recursively concatenates nested arrays while
preserving scalar values and order. This bounded lane covers a nested-array
case; depth-bounded `flatten(n)`, non-array diagnostics, and generator forms
remain deferred.

Oracle source: `upstream/jq/src/builtin.jq:69-71`.

Run with `tools/compat/jq_compat.py` against the pinned jq oracle and Odin
candidate. Expected result: one selected case and one passing case.
