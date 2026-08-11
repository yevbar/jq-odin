# Bounded literal-separator `join` compatibility shard

This shard covers `join("literal")` with the input array supplied by the
surrounding filter. It verifies empty arrays/members and jq's null-as-empty
behavior. The cases are derived from `upstream/jq/tests/jq.test:444-452` and
`upstream/jq/tests/jq.test:1980-1989`.

The parser/compiler contract intentionally accepts only a single literal
string separator. Dynamic separators, multiple separator outputs, numeric or
boolean coercion, and object/array diagnostics remain deferred until a
parameterized-call and tostring contract is available.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/join.jq.test --skips compat/join-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-join-odin --show-passes
```
