# Bounded literal `toboolean`

This shard covers jq's `toboolean` conversion for boolean identity and the
literal strings `"true"` and `"false"`, anchored to the conversion family at
`upstream/jq/tests/jq.test:701-705`. Invalid strings, non-string/non-boolean
inputs, dynamic/map compositions, and exact diagnostic wording remain
deferred.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/toboolean-literal.jq.test \
  --skips compat/toboolean-literal-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-toboolean-459-odin --show-passes
```
