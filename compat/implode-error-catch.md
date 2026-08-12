# Implode caught diagnostics

`implode` now preserves jq's typed diagnostics as caught values for non-array
inputs and nonnumeric array members.

Oracle evidence: `upstream/jq/tests/jq.test:2365`.
