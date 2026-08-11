# Bounded scalar-member `join` compatibility shard

This shard extends the literal-separator `join("literal")` slice to parsed
string, null, number, and boolean array members. Null remains an empty text
member, while numbers and booleans use jq's scalar spellings; scientific
numbers use jq's uppercase `E` and explicit exponent sign. The cases cover
the mixed scalar examples in `upstream/jq/tests/jq.test:1976-1977` and the
adjacent null/scalar behavior in `upstream/jq/tests/jq.test:1980-1989`.

Arrays and objects still produce the existing runtime error. Dynamic
separators, generator-valued separators, and native numbers produced by
arithmetic are intentionally deferred; this lane only broadens parsed scalar
members without changing the Join AST or ownership contract.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/join-scalars.jq.test --skips compat/join-scalars-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-join-coercion-odin --show-passes
```
