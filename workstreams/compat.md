# Compatibility harness workstream

Own a candidate-independent runner that compares pinned jq 1.8.1 with the Odin
CLI. Begin with a small shard of `upstream/jq/tests/jq.test`.

The harness must preserve ordered zero-to-many outputs and support both
semantic JSON comparison and exact byte comparison. It must also represent
compile failures, diagnostics, process status, platform gates, and explicit
skips.

Do not require the Odin candidate to implement jq's internal `--run-tests`
mode.

