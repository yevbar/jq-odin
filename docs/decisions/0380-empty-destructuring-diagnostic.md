# Empty destructuring diagnostics

Status: implemented bounded slice (2026-08-15)

jq rejects `. as [] | null` and `. as {} | null` at the closing delimiter,
with token-specific source diagnostics (jq.test:548 and :554). The parser now
retains that delimiter span and a narrow CLI formatter emits jq-compatible
messages. This does not broaden ordinary empty array/object constructors or
the multi-diagnostic arithmetic-key recovery contract.

Validation: focused driver span tests, package checks, Odin build, and pinned
jq differential probes for both filters.
