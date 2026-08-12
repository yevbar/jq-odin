# Decision 0232: frame lowercase NaN JSON input

The CLI incremental framer distinguishes the shared `n` prefix before choosing
the existing `null` literal or a new bounded lowercase `nan` literal. The
owning JSON parser and Value constructor already accept payload-free NaN, and
the serializer already emits native NaN as `null`, so no public type, opcode,
ownership rule, or package edge changes.

This closes `upstream/jq/tests/jq.test:2277-2279` and unblocks the existing
caught `implode` behavior at `upstream/jq/tests/jq.test:2365-2367`. It follows
the pinned scanner at `upstream/jq/src/jv_parse.c:506-545`, where only `nu...`
is reserved for `null` and other `n...` tokens reach numeric validation. The
focused fixture is `compat/json-input-nan.jq.test`; CLI tests cover every input
split plus an invalid `nanx` suffix.

The framer intentionally remains narrower than the underlying jq/decNumber
parser. Uppercase or signed NaN, zero-payload suffixes, infinity, other
permissive number spellings, and their exact incremental diagnostics are
deferred rather than silently broadening this compatibility slice.
