# Decision 0198: bounded `limit` generators

Implement zero-, one-, and multi-output limiting for literal nonnegative
counts and existing generator streams. The evaluator cancels descendant
frames when the quota is reached, preserving ownership while suppressing later
outputs. Dynamic counts, comma-separated generators, and diagnostic wording
remain deferred.

Oracle evidence: `upstream/jq/tests/jq.test:361-373,420-423`.
