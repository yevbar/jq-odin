# Bounded literal index-family needles

This shard covers numeric and array literal needles for `index`, `rindex`, and
`indices`, matching jq's scalar element and contiguous-subarray behavior from
`upstream/jq/tests/jq.test:1543-1551`. Existing literal string needles and
Unicode code-point offsets remain covered by `compat/index-family.jq.test`.

The parser accepts only statically shaped literals in this lane. Dynamic
needles, empty needles, two-argument forms, Unicode/diagnostic edge cases, and
non-array/string container errors remain deferred. Empty array needles are
rejected rather than assigning jq's broad all-boundaries semantics.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/index-family-needles.jq.test \
  --skips compat/index-family-needles-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-index-array-a01 --show-passes
```
