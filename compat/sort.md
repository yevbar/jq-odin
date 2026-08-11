# `sort` compatibility shard

This shard covers the zero-argument array form of jq's `sort`, including its
cross-type total ordering, nested arrays/objects, strings, and duplicate
preservation. The case is copied from `upstream/jq/tests/jq.test:1635-1637`.

The implementation is intentionally bounded to arrays and delegates ordering
to the evaluator's existing `compare_values` contract. Non-array diagnostics,
sort_by generators, and locale-specific collation remain separate work.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/sort.jq.test --skips compat/sort-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-next-gap-odin --show-passes
```
