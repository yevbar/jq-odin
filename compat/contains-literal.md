# Bounded literal-string `contains` compatibility shard

This shard covers `contains("literal")` when the input is a string. It
includes empty needles, ordinary substrings, and embedded NUL bytes. The
cases are derived from `upstream/jq/tests/jq.test:1404-1427`.

The parser/compiler contract intentionally accepts one literal string argument
only. Array/object recursive containment, dynamic arguments, and general
function-call syntax remain deferred. Non-string inputs therefore retain the
candidate's existing runtime error behavior rather than claiming jq parity.

The parser rejects unsupported non-string literal arguments such as
`contains([2])` and `contains({"a":1})` with a controlled filter parse error
(`rc=3`) after consuming the closing parenthesis. This avoids the previous
assertion crash while preserving the accepted string-literal path. Regression
coverage lives in `src/syntax/parser_test.odin`.

Run with:

```sh
python3 tools/compat/jq_compat.py \
  --tests compat/contains-literal.jq.test \
  --skips compat/contains-literal-skips.json \
  --oracle /private/tmp/jq-merge-next/.tools/jq-oracle-1.8.1 \
  --candidate /tmp/jq-contains-odin --show-passes
```
