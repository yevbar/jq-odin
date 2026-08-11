# fromjson parse diagnostics

This shard covers invalid numeric payloads and malformed quoted object keys
passed through `try ... catch .`. The evaluator retains the parser's jq-facing
message as an owned runtime key. The source cases are
`upstream/jq/tests/jq.test:2282-2291` and `:2456`.
