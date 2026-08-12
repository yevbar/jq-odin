# Decision 0217: implode runtime keys

Status: accepted (2026-08-11).

The evaluator retains jq's typed `implode` diagnostics through the existing
owned runtime-key transport, allowing `try implode catch .` to observe the
message. Valid codepoint encoding is unchanged.

Evidence: `upstream/jq/tests/jq.test:2365`.
