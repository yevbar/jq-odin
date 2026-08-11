# `unique` compatibility shard

This shard covers the bounded zero-argument array form of jq's `unique`:
values are sorted according to jq's normal value ordering and duplicates are
removed. It includes a mixed ordering case, an adjacent duplicate regression
case (`[1,1,2]`), and the empty-array identity case.

The source oracle cases are `upstream/jq/tests/jq.test:1647-1651`.

The Odin implementation intentionally leaves non-array diagnostics and
locale-sensitive/string collation details to a later compatibility lane.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/unique.jq.test --skips compat/unique-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-unique-replay-odin --show-passes
```
