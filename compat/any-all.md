# Zero-argument `any`/`all` compatibility shard

This shard covers jq's zero-argument `any` and `all` filters over input arrays:
empty arrays use the usual identity values (`false` and `true`), and null or
false elements are falsey while all other values are truthy. The five cases
come from `upstream/jq/tests/jq.test:1077-1095`.

The literal `any(not)` and `all(not)` forms are also covered by dedicated
negated-truthiness predicates. Parameterized generators and conditions (`any(generator; condition)`,
`all(generator; condition)`, and `any(generator)`) remain deferred because
they require a continuation/control-flow contract beyond this zero-argument
slice. Non-array diagnostics are also deferred.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/any-all.jq.test --skips compat/any-all-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-anyall-odin --show-passes
```
