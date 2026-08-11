# Bounded literal-string `split` compatibility shard

This shard covers `split("literal")` for string inputs and ordinary non-empty
ASCII separators. It exercises repeated delimiters, leading/trailing empty
segments, empty input, and separators that contain a space. The cases are derived from
`upstream/jq/tests/jq.test:1495-1499` and `1575-1579`.

The parser/compiler contract intentionally accepts one literal string
separator. Empty-separator Unicode code-point behavior, dynamic separators,
array separators, and non-string diagnostics remain deferred.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/split-literal.jq.test \
  --skips compat/split-literal-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-split-odin --show-passes
```
