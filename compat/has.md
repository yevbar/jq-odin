# Bounded literal `has` compatibility shard

This shard covers `has("key")` for object keys, `has(N)` for non-negative
integer array indexes, and the `has(nan)` false result. The cases are derived
from `upstream/jq/tests/jq.test:1687-1695`. Missing keys/indices return false;
null inputs, dynamic arguments, negative indexes, and recursive generator
forms remain deferred.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/has.jq.test --skips compat/has-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-has-odin --show-passes
```
