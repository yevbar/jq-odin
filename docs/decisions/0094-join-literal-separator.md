# Decision 0094: bounded literal-separator `join`

Implement `join("literal")` for arrays whose members are strings or null.
Null members contribute empty text; dynamic separators, generator arguments,
and jq's numeric/boolean/object coercions remain deferred. The opcode is
appended after the current `isfinite` form.

The focused compatibility shard cites `upstream/jq/tests/jq.test:450` and the
simple join cases around lines 1976-1996.
