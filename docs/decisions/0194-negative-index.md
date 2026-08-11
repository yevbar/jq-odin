# Decision 0194: negative array index reads

Literal negative numeric postfix indices are accepted and resolved relative to
the end of arrays (`.[-1]` is the final element). Out-of-range negative reads
yield `null`, matching jq. Negative index assignment, comma-separated index
streams, fractional indices, and string code-point indexing remain deferred.

Evidence: `upstream/jq/tests/jq.test:213-229` covers negative indexing and
assignment boundaries; this slice covers read semantics only.
