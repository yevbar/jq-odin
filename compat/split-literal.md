# Bounded literal-string `split` compatibility shard

This shard covers `split("literal")` for string inputs and ordinary non-empty
ASCII separators. It exercises repeated delimiters, leading/trailing empty
segments, empty input, separators that contain a space, and Unicode codepoint
splitting for an empty separator. The cases are derived from
`upstream/jq/tests/jq.test:1495-1499` and `1575-1579`.

The parser/compiler contract intentionally accepts one literal string
separator. Dynamic separators, array separators, malformed UTF-8, and
non-string diagnostics remain deferred.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/split-literal.jq.test \
  --skips compat/split-literal-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-split-odin --show-passes
```
