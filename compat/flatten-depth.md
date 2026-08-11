# Bounded literal `flatten(depth)` compatibility shard

This shard covers literal non-negative integer depth arguments for `flatten`.
Depth zero preserves each top-level element; positive depths recursively unpack
that many nested array levels. Cases come from
`upstream/jq/tests/jq.test:1761-1773`.

Dynamic depth expressions, negative-depth diagnostics, non-array inputs, and
generator composition remain deferred.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/flatten-depth.jq.test \
  --skips compat/flatten-depth-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-flatten-depth-odin --show-passes
```
