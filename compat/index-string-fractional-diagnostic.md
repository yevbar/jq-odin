# Fractional string-index diagnostics

Numeric indexing of strings reports jq's typed `Cannot index string with
number` message, including fractional indices.

Oracle evidence: `upstream/jq/tests/jq.test:2445`.
