# Definition redefinition and lexical snapshots

The driver now routes filters containing multiple top-level definitions through
the module expander. Its declaration indices preserve jq's lexical behavior:
later redefinitions affect later calls, while a definition body captures the
callee visible at its own declaration.

Focused shard: `compat/definition-redefinition.jq.test`.
