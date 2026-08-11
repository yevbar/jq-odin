# Decision 0162: bounded UTC `strftime` arrays

## Scope

Add an append-only `Strftime` AST/opcode for the literal UTC format
`%Y-%m-%dT%H:%M:%SZ`. The evaluator formats parsed datetime arrays with year,
zero-based month, day, hour, minute, and second fields; omitted trailing time
fields default to zero as in jq.

## Evidence

The direct jq 1.8.1 cases at `upstream/jq/tests/jq.test:1805-1817` establish
the parsed-array formatting contract. `compat/strftime.jq.test` records full
and abbreviated array cases against the pinned oracle.

## Deferred

Numeric timestamps, other directives/local-time behavior, and sibling date
converters (`strptime`, `mktime`, `gmtime`) remain deferred.
