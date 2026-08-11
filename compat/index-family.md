# Bounded literal index-family compatibility shard

This shard covers one literal string argument for `index`, `rindex`, and
`indices` with ASCII string input, plus jq's null and array-input behavior.
String input verifies first/last occurrence and overlapping `indices` results;
indexes are Unicode code-point offsets, matching jq even when the UTF-8 byte
offset differs.
For array input, only exact string elements match (numbers and nulls are
skipped); null input propagates null, and an empty array produces null/null/[]
for index/rindex/indices. The cases are derived from
`upstream/jq/tests/jq.test:1515-1521`, `1555-1557`, and `1559-1571`.

The parser/compiler contract also accepts comma-separated literal string
needles, lowering each to the existing scalar index opcode. Empty needles,
array needles, dynamic arguments, and non-string diagnostics remain deferred.
Array needles
are distinct from the supported array *inputs* and are still out of scope.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/index-family.jq.test \
  --skips compat/index-family-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-index-family --show-passes
```
