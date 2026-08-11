# `nan` and `infinite` compatibility shard

This bounded slice adds the zero-argument `nan` and `infinite` numeric
constants. It checks NaN arithmetic/predicate behavior and jq's serializer
clamping of positive infinity. Evidence comes from
`upstream/jq/tests/jq.test:689-693` and `upstream/jq/tests/jq.test:2271-2278`.

Unary `-infinite` is covered only for the existing `isinfinite` predicate;
general unary negation and JSON parsing of NaN payload strings remain deferred.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/special-numbers.jq.test --skips compat/special-numbers-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-nan-inf-odin --show-passes
```

Oracle source: `upstream/jq/tests/jq.test:689-693,2271-2278`.
