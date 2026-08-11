# `ceil` compatibility shard

The zero-argument `ceil` filter rounds numeric inputs toward positive
infinity. This shard covers positive, negative, and already-integral values;
non-number diagnostic cases remain tracked but are not claimed by this
bounded lane.

Run the shard with the pinned oracle and candidate via
`tools/compat/jq_compat.py`; expected result is one selected case and one
passing case.
