# `atan` compatibility shard

This bounded shard covers the zero-argument scalar `atan` filter for a numeric
input. It uses the exact zero result to avoid coupling this older coordinator
snapshot to a missing `floor` helper; jq's broader precision probe is recorded
at `upstream/jq/tests/jq.test:838`. Non-number diagnostics, non-finite values,
and argument forms remain deferred.

Run with:

```sh
tools/compat/jq_compat.py \
  --tests compat/atan.jq.test \
  --skips compat/atan-skips.json \
  --oracle "$ORACLE" --candidate /absolute/path/to/jq-odin --show-passes
```
